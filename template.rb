require "fileutils"
require "shellwords"

def add_template_to_source_path
  source_paths.unshift(File.dirname(__FILE__))
end

# CLI helpers: read values and flags from the Rails template `options` hash or from raw ARGV.
# - cli_option(name, default) => returns the option value (from options or ARGV --name=value or --name value) or default
# - cli_flag?(name) => returns true if the flag was passed (either in options or as --name in ARGV)
def cli_option(name, default = nil)
  # Normalize names with hyphens to underscore keys for the options hash
  name_str = name.to_s
  key_str = name_str.tr('-', '_')
  key_sym = key_str.to_sym

  # prefer test harness global if present
  opts = defined?($TEMPLATE_OPTIONS) ? $TEMPLATE_OPTIONS : nil

  # try to obtain an options object if available (handles cases where options is a method)
  if opts.nil?
    begin
      opts = options
    rescue NameError, NoMethodError
      opts = nil
    end
  end

  # prefer the `options` hash provided by Rails templates when present
  if opts
    opts_hash = nil
    begin
      opts_hash = opts.to_hash
    rescue NoMethodError, TypeError
      opts_hash = nil
    end

    if opts_hash
      if opts_hash.key?(key_sym)
        return opts_hash[key_sym]
      elsif opts_hash.key?(key_str)
        return opts_hash[key_str]
      elsif opts_hash.key?(name_str)
        return opts_hash[name_str]
      end
    end
  end

  # helper to remove surrounding quotes from a value
  unquote = ->(v) { v.nil? ? v : v.to_s.gsub(/^['"]|['"]$/, '') }

  # parse ARGV: --name=value
  if (arg = ARGV.find { |a| a.start_with?("--#{name_str}=") })
    return unquote.call(arg.split("=", 2)[1])
  end

  # parse ARGV: --name value
  idx = ARGV.index("--#{name_str}")
  if idx && ARGV[idx + 1] && !ARGV[idx + 1].start_with?("--")
    return unquote.call(ARGV[idx + 1])
  end

  default
end

def cli_flag?(name)
  name_str = name.to_s
  key_str = name_str.tr('-', '_')
  key_sym = key_str.to_sym

  # prefer test harness global if present
  opts = defined?($TEMPLATE_OPTIONS) ? $TEMPLATE_OPTIONS : nil

  # try to obtain an options object if available (handles cases where options is a method)
  if opts.nil?
    begin
      opts = options
    rescue NameError, NoMethodError
      opts = nil
    end
  end

  if opts
    opts_hash = nil
    begin
      opts_hash = opts.to_hash
    rescue NoMethodError, TypeError
      opts_hash = nil
    end

    if opts_hash
      if opts_hash.key?(key_sym)
        return !!opts_hash[key_sym]
      elsif opts_hash.key?(key_str)
        return !!opts_hash[key_str]
      elsif opts_hash.key?(name_str)
        return !!opts_hash[name_str]
      end
    end
  end

  # if explicitly provided as --flag=value, interpret common boolean forms
  if (arg = ARGV.find { |a| a.start_with?("--#{name_str}=") })
    val = arg.split("=", 2)[1].to_s.gsub(/^['"]|['"]$/, '')
    return !(val =~ /\A(false|0)\z/i)
  end

  ARGV.any? { |a| a == "--#{name_str}" || a.start_with?("--#{name_str}=") }
end

def user_responses
  say "options: #{options.inspect}"   # useful for exploring what's present
  say "ARGV: #{ARGV.inspect}"         # raw CLI tokens

  @testing_response = ask("Would you like to install RSpec for testing: (Y/n)", :green) if options[:skip_test]
  @testing_response = "y" if @testing_response.blank?
  @styling_response = ask("Would you like to install a style system: bootstrap/tailwind/postcss/sass system? (B/t/p/s)", :green)
  @styling_response = "b" if @styling_response.blank?
  @ssl_response = ask("Would you like to configure SSL for local development: (Y/n)", :green)
  @ssl_response = "y" if @ssl_response.blank?
end

def add_gems
  run "mkdir config/gems"

  copy_file "config/gems/app.rb", "config/gems/app.rb", force: true

  # If the user selected a JavaScript option other than importmap, enable cssbundling-rails
  # by uncommenting the gem in the copied config/gems/app.rb
  js_choice = cli_option(:javascript, options && options[:javascript])
  js_choice = js_choice.to_s if js_choice
  js_choice = "importmap" if js_choice.nil? || js_choice == ""

  if js_choice != "importmap"
    gsub_file "config/gems/app.rb", /#\s*gem\s+['"]cssbundling-rails['"]/, 'gem "cssbundling-rails"'
  end

  inject_into_file "Gemfile", after: "source \"https://rubygems.org\"" do
    "\n\neval_gemfile 'config/gems/app.rb'"
  end

  if @testing_response == "y"
    copy_file "config/gems/rspec_gemfile.rb", "config/gems/rspec_gemfile.rb", force: true
    inject_into_file "Gemfile", after: "eval_gemfile 'config/gems/app.rb'" do
      "\neval_gemfile 'config/gems/rspec_gemfile.rb'"
    end
  elsif @testing_response.nil?
    copy_file "config/gems/minitest_gemfile.rb", "config/gems/minitest_gemfile.rb", force: true
    inject_into_file "Gemfile", after: "eval_gemfile 'config/gems/app.rb'" do
      "\neval_gemfile 'config/gems/minitest_gemfile.rb'"
    end
  end

  system("ruby -v | awk '{print $2}' > .ruby-version")
end

def config_generators
  inject_into_file "config/application.rb", "    config.generators.helper = false", after: "config.generators.system_tests = nil\n"
  inject_into_file "config/application.rb", "    config.generators.stylesheets = false\n\n", after: "config.generators.helper = false\n"
end

def add_static
  generate "controller static home"

  route "root to: 'static#home'"
end

def setup_styling
  add_javascript

  if @styling_response == "b"
    add_bootstrap
  elsif @styling_response == "t"
    add_tailwind
  elsif @styling_response == "p"
    add_postcss
  else
    add_sass
  end
end

def add_javascript
  run "yarn add chokidar -D"

  run "echo | node -v | cut -c 2- > .node-version"

  directory "app", force: true

  insert_into_file "app/javascript/application.js", after: "import \"./controllers\"\n" do
    "\nimport \"./controllers/third_party_controllers\"\n"
  end
end

def add_esbuild_script
  copy_file "esbuild.config.mjs"
  build_script = "node esbuild.config.mjs"

  case `npx -v`.to_f
  when 7.1...8.0
    run %(npm set-script build "#{build_script}")
    run %(yarn build)
  when (8.0..)
    run %(npm pkg set scripts.build="#{build_script}")
    run %(yarn build)
  else
    say %(Add "scripts": { "build": "#{build_script}" } to your package.json), :green
  end
end

def add_bootstrap
  rails_command "css:install:bootstrap"
  add_esbuild_script

  directory "app_bootstrap", "app", force: true

  add_esbuild_script
end

def add_tailwind
  rails_command "css:install:tailwind"

  run "yarn add flowbite postcss-import postcss-nested"

  directory "app_tailwind", "app", force: true
  copy_file "tailwind.config.js", "tailwind.config.js", force: true
  copy_file "tailwind_postcss.config.js", "postcss.config.js", force: true
  gsub_file "package.json", "tailwindcss -i ./app/assets/stylesheets/application.tailwind.css -o ./app/assets/builds/application.css --minify", "tailwindcss --postcss -i ./app/assets/stylesheets/application.tailwind.css -o ./app/assets/builds/application.css --minify"

  add_esbuild_script
end

def add_postcss
  rails_command "css:install:postcss"

  directory "app_postcss", "app", force: true
  add_esbuild_script
end

def add_sass
  rails_command "css:install:sass"

  directory "app_sass", "app", force: true
  add_esbuild_script
end

def copy_templates
  copy_file ".editorconfig", force: true
  copy_file ".erb-lint.yml", force: true
  copy_file ".erdconfig", force: true
  copy_file ".gitignore", force: true
  copy_file "esbuild.config.mjs", force: true
  copy_file ".rubocop.yml", force: true
  copy_file ".rubocop_todo.yml", force: true
  copy_file "Brewfile"

  directory "bin", force: true
  directory "docs", force: true
  directory "lib", force: true

  environment "config.action_mailer.default_url_options = { host: 'localhost', port: 3000 }", env: "development"
  environment "config.action_mailer.default_url_options = { host: 'example.com' }", env: "test"
end

def setup_testing
  if @testing_response == "y"

    gsub_file "bin/ci", "bin/rails test", "bin/rspec"

    copy_file ".rspec"
    directory "spec", force: true
  else
    copy_file "test/test_helper.rb", force: true
  end
end

def config_gems
  rails_command "generate annotate:install"

  inject_into_file "config/routes.rb", after: "Rails.application.routes.draw do\n" do
    <<-RUBY
  mount LetterOpenerWeb::Engine, at: "/letter_opener" if Rails.env.development?\n
    RUBY
  end
end

def database_setup
  rails_command("db:create")
  rails_command("db:migrate")
end

def command_available?(command)
  system("command -v #{command} >/dev/null 2>&1")
end

def run_setup
  # Install system dependencies if Homebrew is installed
  if command_available?("brew")
    system("brew bundle check --no-upgrade")
  end
end

def local_ssl
  return unless @ssl_response == "y"

  run "mkdir config/certs"
  run "mkcert -cert-file config/certs/localhost.crt -key-file config/certs/localhost.key localhost"

  inject_into_file "config/puma.rb", after: "worker_timeout 3600" do
    <<~RUBY
        \n
        ssl_bind(
        "0.0.0.0",
        3001,
        key: ENV.fetch("SSL_KEY_FILE", "config/certs/localhost.key"),
        cert: ENV.fetch("SSL_CERT_FILE", "config/certs/localhost.crt"),
        verify_mode: "none"
      )
    RUBY
  end

  gsub_file "Procfile.dev", "bin/rails server", "bin/bundle exec puma -C config/puma.rb"
end

def add_binstubs
  run "bundle binstub rubocop"
  run "bundle binstub rspec-core" if @testing_response == "y"
end

def lint_code
  run "bundle exec rubocop -a"

  run "bundle exec erblint --lint-all -a"
end

def initial_commit
  run "git init"
  run "git add . && git commit -m \"Initial_commit\""
end

# Add support for test harness: if $TEMPLATE_OPTIONS is set, prefer it as the options source
if defined?($TEMPLATE_OPTIONS)
  def options
    $TEMPLATE_OPTIONS
  end
end

# Main setup
add_template_to_source_path

user_responses

add_gems

after_bundle do
  setup_styling
  copy_templates
  config_generators
  add_static
  setup_testing
  config_gems
  database_setup
  run_setup
  local_ssl
  add_binstubs
  lint_code
  initial_commit

  say
  say "Rails app successfully created!", :blue
  say
  say "To get started with your new app:", :green
  say "  cd #{app_name}"
end
