require "fileutils"
require "shellwords"
require_relative "scripts/template_cli_helpers"
require_relative "scripts/gem_manager"

def add_template_to_source_path
  source_paths.unshift(File.dirname(__FILE__))
end

def js_choice
  return @js_choice if defined?(@js_choice) && !@js_choice.nil?

  raw = TemplateCLI.cli_option(:javascript, options && options[:javascript])
  raw = raw.to_s if raw
  raw = "importmap" if raw.nil? || raw == ""
  @js_choice = raw
end

# Helper to determine whether tests should be skipped.
# Checks in order:
# 1) TemplateCLI helper flag if available
# 2) the local `options` hash (when provided by template invocation)
# 3) the global `$TEMPLATE_OPTIONS` (when set by external callers)
# 4) direct CLI args in ARGV for `-T` or `--skip-test`
# This ensures that if any of these surfaces request skipping tests, the
# interactive test prompt is never shown and test dirs are removed.
def skip_tests?
  # TemplateCLI-level flag (preferred)
  if defined?(TemplateCLI) && TemplateCLI.respond_to?(:cli_flag?)
    return true if TemplateCLI.cli_flag?(:skip_test)
  end

  # options provided by template invocations (e.g. via options method)
  if defined?(options) && options
    return true if options[:skip_test] || options['skip_test'] || options[:'skip-test'] || options['skip-test']
  end

  # Add support for external callers that set $TEMPLATE_OPTIONS
  if defined?($TEMPLATE_OPTIONS) && $TEMPLATE_OPTIONS
    return true if $TEMPLATE_OPTIONS[:skip_test] || $TEMPLATE_OPTIONS['skip_test'] || $TEMPLATE_OPTIONS[:'skip-test'] || $TEMPLATE_OPTIONS['skip-test']
  end

  # direct CLI flags
  if defined?(ARGV) && ARGV.respond_to?(:any?) && ARGV.any?
    return true if ARGV.any? { |a| a == '-T' || a == '--skip-test' }
  end

  false
end

def user_responses
  raw_js = TemplateCLI.cli_option(:javascript, (defined?(options) ? options && options[:javascript] : nil))
  raw_js = raw_js.to_s if raw_js
  raw_js = "importmap" if raw_js.nil? || raw_js == ""
  @js_choice = raw_js

  # Prefer TemplateCLI helper which reads ARGV, $TEMPLATE_OPTIONS, and options where available
  if skip_tests?
    @testing_response = nil
  else
    answer = ask("Would you like to install RSpec for testing: (Y/n)", :green)
    if answer.blank?
      @testing_response = "y"
    else
      @testing_response = answer.strip.downcase.start_with?("y") ? "y" : "n"
    end
  end

  @styling_response = ask("Would you like to install a style system: bootstrap/tailwind/postcss/sass system? (B/t/p/s)", :green)
  @styling_response = "b" if @styling_response.blank?
end

def add_gems
  # Delegate to the script helper to keep the template thin and testable.
  GemManager.apply(self)
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
  return if js_choice == "importmap"

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
  directory "app_bootstrap_importmap", "app", force: true

  unless File.exist?("bin/importmap")
    begin
      rails_command "importmap:install"
    rescue
      if File.exist?("bin/rails")
        system("bin/rails importmap:install")
      else
        system("bundle exec rails importmap:install")
      end
    end
  end

  if File.exist?("bin/importmap")
    # Use the simple non-download pin command; do not attempt CA fixes or local installs.
    if system("bin/importmap pin bootstrap")
      say "Pinned bootstrap via importmap (no download)", :green
    else
      say "Warning: failed to pin bootstrap via importmap. You can run 'bin/importmap pin bootstrap' manually.", :red
    end
  else
    say "bin/importmap not found; skipping importmap pinning for bootstrap", :yellow
  end

  app_js = "app/javascript/application.js"
  if File.exist?(app_js)
    say "Adding import for bootstrap in #{app_js}", :green
    File.read(app_js)
    insert_into_file "app/javascript/application.js", before: "import \"controllers\"\n" do
      "import \"bootstrap\"\n"
    end
  else
    say "Warning: #{app_js} not found; cannot add bootstrap import", :red
  end

  system("rm app/assets/stylesheets/application.css") if File.exist?("app/assets/stylesheets/application.css")
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
  copy_file "esbuild.config.mjs", force: true if js_choice == "esbuild"
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
  # Finalize test setup: make sure only the selected framework is present
  if @testing_response == "y"
    # RSpec selected: remove minitest artifacts and Gemfile evals
    if File.exist?("Gemfile")
      gsub_file "Gemfile", /\n*eval_gemfile\s+'config\/gems\/minitest_gemfile.rb'\s*\n*/m, ''
      if File.exist?("config/gems/minitest_gemfile.rb")
        minitest_gems = File.read("config/gems/minitest_gemfile.rb").scan(/gem\s+['"]([^'"]+)['"]/).flatten
        minitest_gems.each do |g_name|
          gsub_file "Gemfile", /^\s*gem\s+['"]#{Regexp.escape(g_name)}['\"].*\n/, ''
        end
      end
    end

    # Remove test directory (cleanup prior/minitest runs)
    run "rm -rf test" if Dir.exist?("test")

    # Install RSpec artifacts
    gsub_file "bin/cleanup", "bin/rails test", "bin/rspec" if File.exist?("bin/cleanup")
    copy_file ".rspec" if File.exist?(".rspec") || File.exist?("config/gems/rspec_gemfile.rb")
    directory "app_spec", "spec", force: true
  elsif @testing_response == "n"
    # Minitest selected: remove RSpec artifacts and Gemfile evals
    if File.exist?("Gemfile")
      gsub_file "Gemfile", /\n*eval_gemfile\s+'config\/gems\/rspec_gemfile.rb'\s*\n*/m, ''
      if File.exist?("config/gems/rspec_gemfile.rb")
        rspec_gems = File.read("config/gems/rspec_gemfile.rb").scan(/gem\s+['"]([^'"]+)['"]/).flatten
        rspec_gems.each do |g_name|
          gsub_file "Gemfile", /^\s*gem\s+['"]#{Regexp.escape(g_name)}['\"].*\n/, ''
        end
      end
    end

    # Remove spec directory and .rspec
    run "rm -rf spec" if Dir.exist?("spec")
    run "rm -f .rspec" if File.exist?(".rspec")

    # Install Minitest artifacts
    copy_file "test/test_helper.rb", force: true
  else
    # Tests skipped; remove any RSpec or Minitest helper files to be clean
    run "rm -rf test" if Dir.exist?("test")
    run "rm -rf spec" if Dir.exist?("spec")
    run "rm -f .rspec" if File.exist?(".rspec")
  end
end

def config_gems
  rails_command "generate annotate:install"

  rails_command "dartsass:install"

  if js_choice == "importmap"
    if @styling_response == "b"
      inject_into_file "app/assets/stylesheets/application.scss", prepend: "" do
        <<-SCSS
  @import "customized_bootstrap";
  @import "bootstrap";
  @import "custom";
        SCSS
      end
    end
  end

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

def add_binstubs
  run "bundle binstub rubocop"
  run "bundle binstub rspec-core" if @testing_response == "y"
end

def lint_code
  run "bundle exec rubocop -a"

  run "bundle exec erb_lint --lint-all -a"
end

def initial_commit
  run "git init"
  run "git add . && git commit -m \"Initial_commit\""
end

# Complex importmap helpers removed: we standardize on running `bin/importmap pin <pkg>` directly.
# The previous code attempted CA retries, CDN fallbacks, and local npm installs; that is intentionally
# removed to keep the template simple and predictable.

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
  add_binstubs
  lint_code
  initial_commit

  say
  say "Rails app successfully created!", :blue
  say
  say "To get started with your new app:", :green
  say "  cd #{app_name}"
end

