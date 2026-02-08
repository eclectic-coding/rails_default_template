require "fileutils"
require "shellwords"
require_relative "scripts/template_cli_helpers"
require_relative "scripts/gem_manager"

def add_template_to_source_path
  source_paths.unshift(File.dirname(__FILE__))
end

def js_choice
  return @js_choice if defined?(@js_choice) && !@js_choice.nil?

  raw = TemplateCLI.cli_option(:javascript, (defined?(options) ? options && options[:javascript] : nil))
  raw = raw.to_s.strip.downcase if raw
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
  raw_js = raw_js.to_s.strip.downcase if raw_js
  raw_js = "importmap" if raw_js.nil? || raw_js == ""
  @js_choice = raw_js

  # Determine whether the JavaScript option was explicitly provided by the caller
  provided_js = false
  if defined?($TEMPLATE_OPTIONS) && $TEMPLATE_OPTIONS
    provided_js = true if $TEMPLATE_OPTIONS.key?(:javascript) || $TEMPLATE_OPTIONS.key?('javascript') || $TEMPLATE_OPTIONS.key?(:'javascript') || $TEMPLATE_OPTIONS.key?('javascript')
  end


  if !provided_js && defined?(ARGV) && ARGV.respond_to?(:any?) && ARGV.any?
    ARGV.each_with_index do |a, i|
      if a == '--javascript'
        # explicit flag followed by value (if any) -> consider explicit
        provided_js = true if ARGV[i + 1] && !ARGV[i + 1].start_with?('--')
      elsif a.start_with?('--javascript=')
        val = a.split('=', 2)[1].to_s.strip.downcase
        # treat non-default values as explicit; if it's the default 'importmap', treat as not explicit
        provided_js = true unless val == '' || val == 'importmap'
      end
    end
  end

  # Only ask interactively when no explicit javascript option was provided.
  unless provided_js
    # Match styling prompt style: use letters with capital default shown first.
    ans = ask("Which JavaScript bundling would you like? (I/e/b/w/r) [I]", :green)
    chosen = ans.to_s.strip.downcase
    # default to the letter for importmap (same style as the styling prompt which defaults to 'b')
    chosen = "i" if chosen == ""

    # Allow single-letter shortcuts mapping to full names
    shortcuts = {
      'i' => 'importmap',
      'e' => 'esbuild',
      'b' => 'bun',
      'w' => 'webpack',
      'r' => 'rollup'
    }

    # If user typed a single letter, map it; otherwise accept full name
    if shortcuts.key?(chosen)
      chosen = shortcuts[chosen]
    end

    # Accept only known choices; fallback to importmap on unknown input
    allowed = %w[importmap esbuild bun webpack rollup]
    @js_choice = allowed.include?(chosen) ? chosen : 'importmap'
  end

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

  # Let Rails set up the chosen javascript runtime (esbuild/bun/webpack/rollup)
  begin
    rails_command "javascript:install:#{js_choice}"
  rescue
    # Fallback: try invoking bin/rails if present, or bundle exec
    if File.exist?("bin/rails")
      system("bin/rails javascript:install:#{js_choice}")
    else
      system("bundle exec rails javascript:install:#{js_choice}")
    end
  end

  run "yarn add chokidar -D"

  run "echo | node -v | cut -c 2- > .node-version"

  directory "app", force: true

  insert_into_file "app/javascript/application.js", after: "import \"./controllers\"\n" do
    "\nimport \"./controllers/third_party_controllers\"\n"
  end
end

def add_esbuild_script
  copy_file "esbuild.config.mjs"
  # Ensure esbuild package is available for the build; install it as a dev dependency when possible.
  build_script = "node esbuild.config.mjs"

  if js_choice == "esbuild"
    installed = false

    if system("command -v yarn >/dev/null 2>&1")
      say "Installing esbuild via yarn...", :green
      installed = system("yarn add esbuild -D")
    elsif system("command -v npm >/dev/null 2>&1")
      say "Installing esbuild via npm...", :green
      installed = system("npm install esbuild --save-dev")
    else
      say "No yarn or npm available to install esbuild automatically.", :yellow
      installed = false
    end

    unless installed
      say "Warning: esbuild was not installed; skipping automatic esbuild build. After creating the app run 'yarn add esbuild -D' (or 'npm install esbuild --save-dev') and then run the build manually.", :yellow
      return
    end

    # Run the esbuild config directly once to generate builds and validate installation.
    say "Running esbuild config to build JS assets...", :green
    if system(build_script)
      say "esbuild build completed", :green
    else
      say "Warning: esbuild build failed. You can run 'node esbuild.config.mjs' manually after checking that esbuild is installed.", :red
    end
  else
    # For non-esbuild setups we still keep the esbuild config file in case users want it,
    # but we don't run any build or install esbuild.
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
  return unless js_choice == "importmap"

  directory "app_bootstrap_importmap", "app", force: true

  unless File.exist?("bin/importmap")
    # Try to run the importmap installer quietly. Suppress the noisy error output
    # from failed attempts and present a single friendly warning if it fails.
    installed = false

    # First, try using rails_command but silence stdout/stderr while running it.
    begin
      dev_null = File::NULL
      old_stdout = $stdout
      old_stderr = $stderr
      $stdout = File.open(dev_null, "w")
      $stderr = File.open(dev_null, "w")
      begin
        rails_command "importmap:install"
        installed = true
      rescue
        installed = false
      ensure
        $stdout.close unless $stdout == old_stdout
        $stderr.close unless $stderr == old_stderr
        $stdout = old_stdout
        $stderr = old_stderr
      end
    rescue
      # If redirecting fails for some reason, continue to fallbacks
      installed = false
    end

    # Fallback: invoke bin/rails or bundle exec rails, capture output quietly
    unless installed
      begin
        require 'open3'
        if File.exist?("bin/rails")
          cmd = "bin/rails importmap:install"
        else
          cmd = "bundle exec rails importmap:install"
        end

        out, err, status = Open3.capture3(cmd)
        installed = status.success?
      rescue LoadError, StandardError
        installed = false
      end
    end

    unless installed
      say "Skipping importmap installer: 'importmap:install' isn't available or failed. The template will continue and clean up any importmap artifacts; you can run 'bin/rails importmap:install' manually if you want importmap support.", :yellow
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
    insert_into_file "app/javascript/application.js", before: "import \"controllers\"\n" do
      "import \"bootstrap\"\n"
    end
  else
    say "Warning: #{app_js} not found; cannot add bootstrap import", :red
  end

  # Tests stub `system`, so call `rm` directly to avoid unstubbed `File.exist?` calls in specs.
  system("rm app/assets/stylesheets/application.css")
end

def add_bootstrap_js
  add_javascript

  rails_command "css:install:bootstrap"
  # CSS installers sometimes add importmap-related files when a JS bundler isn't detected; ensure they're removed
  remove_importmap_artifacts
  add_esbuild_script

  directory "app_bootstrap", "app", force: true
end

def add_tailwind
  # Tailwind requires JS tooling for the build step in non-importmap setups
  add_javascript

  rails_command "css:install:tailwind"

  # Clean up any importmap artifacts that might have been created by the installer
  remove_importmap_artifacts

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

  # Ensure importmap artifacts are removed if present
  remove_importmap_artifacts

  directory "app_postcss", "app", force: true
  add_esbuild_script
end

def add_sass
  add_javascript

  rails_command "css:install:sass"

  # Ensure importmap artifacts are removed if present
  remove_importmap_artifacts

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

  # Only install dartsass when using importmap (no JS bundler) since bundlers may handle Sass builds
  rails_command "dartsass:install" if js_choice == "importmap"

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

def remove_importmap_artifacts
  return if js_choice == "importmap"

  # Remove common importmap artifacts that Rails generators may have created
  files = Dir.glob('{bin/importmap*,config/importmap.rb,config/importmap/*,app/assets/javascripts/importmap*,app/javascript/importmap*}', File::FNM_DOTMATCH)
  files.each do |p|
    begin
      FileUtils.rm_f(p)
    rescue
      # ignore removal errors
    end
  end

  # Clean up Gemfile references to importmap-rails or eval_gemfile lines for importmap
  if File.exist?("Gemfile")
    begin
      gsub_file "Gemfile", /eval_gemfile\s+'config\/(gems\/)?importmap.*\n?/, ''
      gsub_file "Gemfile", /^\s*gem\s+['\"]importmap-rails['\"].*\n?/, ''
      # If we removed importmap entries, update the bundle to reflect the change so importmap isn't installed
      begin
        run "bundle install --quiet"
      rescue
        # ignore bundle install failures; user can run bundle install manually
      end
    rescue
      # ignore gsub errors
    end
  end
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

remove_importmap_artifacts

add_gems

after_bundle do
  setup_styling
  # If the user selected a JS bundler (not importmap), remove any importmap artifacts
  # that Rails may have installed by default earlier in the generation process.
  if js_choice != "importmap"
    # Remove common importmap artifacts if they exist
    %w[bin/importmap config/importmap.rb].each do |p|
      run "rm -f #{p}" if File.exist?(p)
    end
  end
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

  # Final cleanup: ensure importmap artifacts aren't left behind when a bundler was selected
  remove_importmap_artifacts

  say
  say "Rails app successfully created!", :blue
  say
  say "To get started with your new app:", :green
  say "  cd #{app_name}"
end

