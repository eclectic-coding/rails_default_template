require "fileutils"
require "shellwords"
require "open3"
require 'net/http'
require_relative "script/template_cli_helpers"

def add_template_to_source_path
  source_paths.unshift(File.dirname(__FILE__))
end

# Memoized JS choice helper so we only query TemplateCLI once
def js_choice
  return @js_choice if defined?(@js_choice) && !@js_choice.nil?

  raw = TemplateCLI.cli_option(:javascript, options && options[:javascript])
  raw = raw.to_s if raw
  raw = "importmap" if raw.nil? || raw == ""
  @js_choice = raw
end


def user_responses
  # Capture JS choice early so it's stable for later steps (options/ARGV can change later)
  raw_js = TemplateCLI.cli_option(:javascript, (defined?(options) ? options && options[:javascript] : nil))
  raw_js = raw_js.to_s if raw_js
  raw_js = "importmap" if raw_js.nil? || raw_js == ""
  @js_choice = raw_js

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

  if js_choice == "importmap"
    begin
      gsub_file "config/gems/app.rb", /^#\s*gem\s+['"]bootstrap['"].*$/, 'gem "bootstrap", "~> 5.3.3"'
    rescue => _e
      # ignore if no-op
    end

    begin
      gsub_file "config/gems/app.rb", /^#\s*gem\s+['"]dartsass-rails['"].*$/, 'gem "dartsass-rails"'
    rescue => _e
      # ignore
    end

    # If they don't exist at all, append them
    app_rb = File.read("config/gems/app.rb")
    unless app_rb.include?("gem \"bootstrap\"")
      append_to_file "config/gems/app.rb", "\ngem \"bootstrap\", \"~> 5.3.3\"\n"
    end
    unless app_rb.include?("gem \"dartsass-rails\"")
      append_to_file "config/gems/app.rb", "gem \"dartsass-rails\"\n"
    end
  else
    # For bundler-based flows, prefer cssbundling-rails; comment out bootstrap/dartsass if present
    begin
      gsub_file "config/gems/app.rb", /^(gem\s+\"bootstrap\".*)$/, '# \1'
    rescue => _e
    end
    begin
      gsub_file "config/gems/app.rb", /^(gem\s+\"dartsass-rails\".*)$/, '# \1'
    rescue => _e
    end
  end

  # If the user selected a JavaScript option other than importmap, enable cssbundling-rails
  # by uncommenting the gem in the copied config/gems/app.rb
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
  js_choice # populates @js_choice via the helper
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
  return if defined?(@js_choice) && @js_choice == "importmap"

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
  if js_choice == "importmap"
    add_bootstrap_importmap
  else
    add_bootstrap_js
  end
end

def add_bootstrap_importmap
  directory "app_bootstrap", "app", force: true

  unless File.exist?("bin/importmap")
    begin
      rails_command "importmap:install"
    rescue => _e
      if File.exist?("bin/rails")
        system("bin/rails importmap:install")
      else
        system("bundle exec rails importmap:install")
      end
    end
  end

  if File.exist?("bin/importmap")
    if system("bin/importmap pin bootstrap")
      say "Pinned bootstrap to importmap (via CDN)", :green
    else
      say "Warning: failed to pin bootstrap with importmap. You can run 'bin/importmap pin bootstrap' manually.", :yellow
    end
  else
    say "bin/importmap not found; skipping importmap pinning for bootstrap", :yellow
  end

  app_js = "app/javascript/application.js"
  if File.exist?(app_js)
    content = File.read(app_js)
    unless content.include?("import \"bootstrap\"") || content.include?("bootstrap")
      insert_into_file app_js, after: "import \"./controllers\"\n" do
        "\nimport \"bootstrap\"\n"
      end
    end
  end
end

def add_bootstrap_js
  add_javascript

  rails_command "css:install:bootstrap"
  add_esbuild_script

  directory "app_bootstrap", "app", force: true
end

def add_tailwind
  # Tailwind requires JS tooling for the build step in non-importmap setups
  add_javascript

  rails_command "css:install:tailwind"

  run "yarn add flowbite postcss-import postcss-nested"

  directory "app_tailwind", "app", force: true
  copy_file "tailwind.config.js", "tailwind.config.js", force: true
  copy_file "tailwind_postcss.config.js", "postcss.config.js", force: true
  gsub_file "package.json", "tailwindcss -i ./app/assets/stylesheets/application.tailwind.css -o ./app/assets/builds/application.css --minify", "tailwindcss --postcss -i ./app/assets/stylesheets/application.tailwind.css -o ./app/assets/builds/application.css --minify"

  add_esbuild_script
end

def add_postcss
  add_javascript

  rails_command "css:install:postcss"

  directory "app_postcss", "app", force: true
  add_esbuild_script
end

def add_sass
  add_javascript

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

def pin_pkg_to_cdn(pkg)
  # Map known packages to safe CDN URLs (ES module builds when available).
  # These use npm endpoints on jsDelivr. Using @latest allows resolving without contacting importmap packager.
  case pkg
  when '@popperjs/core'
    url = "https://cdn.jsdelivr.net/npm/@popperjs/core@latest/dist/esm/index.js"
  when 'bootstrap'
    url = "https://cdn.jsdelivr.net/npm/bootstrap@latest/dist/js/bootstrap.esm.min.js"
  else
    # Generic fallback: try the package's module entry via jsdelivr
    url = "https://cdn.jsdelivr.net/npm/#{pkg}@latest"
  end

  cmd = "bin/importmap pin #{pkg} --to #{Shellwords.escape(url)}"
  out, err, status = Open3.capture3(cmd)
  if status.success?
    say "Pinned #{pkg} to CDN URL #{url}", :green
    true
  else
    say "Failed to pin #{pkg} to CDN URL #{url}: #{err.lines.first(3).join(' ').strip}", :red
    false
  end
end
