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

    # Ensure openssl gem is present for importmap Ruby/OpenSSL issues
    begin
      gsub_file "config/gems/app.rb", /^#\s*gem\s+['"]openssl['"].*$/, 'gem "openssl", "~> 3.3", ">= 3.3.2"'
    rescue => _e
      # ignore if no-op
    end

    # If they don't exist at all, append them
    app_rb = File.read("config/gems/app.rb")

    # Build list of gem lines to insert (skip ones already present)
    gems_to_add = []
    gems_to_add << "gem \"bootstrap\", \"~> 5.3.3\"\n" unless app_rb.match(/gem\s+[\"']bootstrap[\"']/)
    gems_to_add << "gem \"dartsass-rails\"\n" unless app_rb.match(/gem\s+[\"']dartsass-rails[\"']/)
    gems_to_add << "gem \"openssl\", \"~> 3.3\", \">= 3.3.2\"\n" unless app_rb.match(/gem\s+[\"']openssl[\"']/)

    if gems_to_add.any?
      path = "config/gems/app.rb"
      lines = File.read(path).lines

      # Remove any existing lines for the gems we intend to add to avoid duplicates
      gem_patterns = [/^\s*gem\s+["']bootstrap["']/, /^\s*gem\s+["']dartsass-rails["']/, /^\s*gem\s+["']openssl["']/]
      lines.reject! do |l|
        gem_patterns.any? { |pat| l =~ pat }
      end

      # find index of the commented strong_migrations line
      idx = lines.index { |l| l =~ /#\s*gem\s+['"]strong_migrations['"]/ }

      insert_block = gems_to_add.join

      if idx
        # Insert after the strong_migrations comment
        insert_at = idx + 1
        lines.insert(insert_at, insert_block)
      else
        # Append at end
        lines << "\n" unless lines.last&.end_with?("\n")
        lines << insert_block
      end

      # Write back the file in one go
      File.write(path, lines.join)
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

  # Insert eval_gemfile 'config/gems/app.rb' into the Gemfile. Prefer placing it after a commented
  # strong_migrations line if present so it's easy for users to find and toggle strong_migrations.
  gemfile_path = "Gemfile"
  if File.exist?(gemfile_path)
    gemfile_content = File.read(gemfile_path)
    strong_line = gemfile_content.lines.find { |l| l =~ /#\s*gem\s+['"]strong_migrations['"]/ }

    if strong_line
      inject_into_file gemfile_path, after: strong_line do
        "\n\neval_gemfile 'config/gems/app.rb'\n"
      end
    else
      inject_into_file gemfile_path, after: "source \"https://rubygems.org\"" do
        "\n\neval_gemfile 'config/gems/app.rb'\n"
      end
    end
  else
    # Fallback to originally inject when Gemfile is missing for some reason
    inject_into_file "Gemfile", after: "source \"https://rubygems.org\"" do
      "\n\neval_gemfile 'config/gems/app.rb'\n"
    end
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
    # Prefer the importmap packager download first (with CA retry) to avoid adding yarn/npm deps.
    pinned = importmap_pin_with_ca_retry("bootstrap")

    if pinned
      say "Pinned bootstrap with download via importmap", :green
    else
      # Packager download failed (likely SSL). Prefer pinning to a known CDN ESM URL rather than
      # installing local node deps. This avoids adding yarn/npm when using importmap.
      if pin_pkg_to_cdn("bootstrap")
        say "Pinned bootstrap to CDN URL via importmap", :green
      else
        # As a last resort, try pin without download (remote CDN URL will be used by browser)
        say "Attempting non-download importmap pin as last resort (remote URL will be used)", :yellow
        if system("bin/importmap pin bootstrap")
          say "Pinned bootstrap without download", :green
        else
          say "Warning: failed to pin bootstrap via importmap. You can run 'bin/importmap pin bootstrap --download' after fixing SSL or run 'bin/importmap pin bootstrap' manually.", :red
        end
      end
    end
  else
    say "bin/importmap not found; skipping importmap pinning for bootstrap", :yellow
  end

  app_js = "app/javascript/application.js"
  if File.exist?(app_js)
    say "Adding import for bootstrap in #{app_js}", :green
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

# Try to locate a Homebrew-provided CA bundle (common on macOS). If none is found and Homebrew exists,
# optionally attempt to install the `ca-certificates` formula and then locate the bundle again.
def find_or_install_homebrew_ca_cert(try_install: true)
  return nil unless command_available?("brew")

  brew_prefix = `brew --prefix`.strip
  candidates = [
    File.join(brew_prefix, "opt", "ca-certificates", "cert.pem"),
    File.join(brew_prefix, "opt", "openssl@3", "libexec", "etc", "openssl", "cert.pem"),
    File.join(brew_prefix, "etc", "openssl", "cert.pem"),
    File.join(brew_prefix, "etc", "openssl@1.1", "cert.pem"),
    File.join(brew_prefix, "etc", "ca-certificates", "cert.pem"),
    '/etc/ssl/cert.pem',
    '/etc/ssl/certs/ca-certificates.crt',
    '/usr/local/etc/openssl/cert.pem'
  ]

  found = candidates.find { |p| p && File.exist?(p) }
  return found if found

  return nil unless try_install

  # Try to install ca-certificates via Homebrew to get a cert bundle.
  begin
    say "No CA bundle found; attempting to install 'ca-certificates' via Homebrew...", :yellow
    if system("brew install ca-certificates")
      # After install, Homebrew places certs under opt/ca-certificates
      candidate = File.join(brew_prefix, "opt", "ca-certificates", "cert.pem")
      return candidate if File.exist?(candidate)
    else
      say "Homebrew install of ca-certificates failed or was skipped.", :yellow
    end
  rescue => e
    say "Homebrew install attempt failed: #{e.message}", :yellow
  end

  # final attempt without installation
  candidates.find { |p| p && File.exist?(p) }
rescue
  nil
end

# Run `bin/importmap pin <pkg> --download` with optional SSL_CERT_FILE env retry.
# This function will try a Homebrew CA bundle and even attempt to install the bundle if brew is available.
# Returns true when the importmap command succeeded (downloaded), false otherwise.
def importmap_pin_with_ca_retry(pkg)
  return false unless File.exist?("bin/importmap")

  cmd = ["bin/importmap", "pin", pkg, "--download"]

  # Try without special env first (capture output)
  _, err, status = Open3.capture3(*cmd)
  return true if status.success?

  # If it failed and looks like an SSL cert verification issue, try with a CA bundle
  if err =~ /certificate verify failed|SSL_connect returned|OpenSSL::SSL::SSLError/i
    # Prefer an explicit SSL_CERT_FILE if already configured in the environment
    env_cert = ENV['SSL_CERT_FILE']
    cert = env_cert && File.exist?(env_cert) ? env_cert : find_or_install_homebrew_ca_cert(try_install: true)

    unless cert
      say "Importmap pin failed due to SSL verification and no CA bundle detected. You can try installing ca-certificates via Homebrew and setting SSL_CERT_FILE, for example:\n  export SSL_CERT_FILE=\"$(brew --prefix)/opt/ca-certificates/cert.pem\"", :yellow
      return false
    end

    env = {
      'SSL_CERT_FILE' => cert,
      'SSL_CERT_DIR' => File.dirname(cert),
      'CURL_CA_BUNDLE' => cert
    }

    say "Retrying importmap pin for #{pkg} with SSL_CERT_FILE=#{cert}", :yellow

    # Make the CA bundle available to this process so children inherit it
    ENV['SSL_CERT_FILE'] = cert
    ENV['SSL_CERT_DIR'] = File.dirname(cert)
    ENV['CURL_CA_BUNDLE'] = cert

    # Try system() first (more direct for child process behavior)
    if system(*cmd)
      return true
    end

    # If system() failed, use capture3 to capture diagnostics (child inherits ENV already)
    out2, err2, status2 = Open3.capture3(*cmd)
    if status2.success?
      return true
    else
      last_err = (err2 && !err2.empty?) ? err2 : err
      say "Importmap pin retry still failed: #{last_err.lines.first(8).join(' ').strip}", :red
      return false
    end
  else
    # Non-SSL failure; show a short error and return false
    say "Importmap pin failed: #{err.lines.first(3).join(' ').strip}", :red
    return false
  end
end

# Attempt to install Bootstrap locally (via yarn or npm), copy ESM build into app/assets/javascripts,
# and add a local importmap pin pointing to /assets/<file>. Returns true on success.
def local_install_and_pin_bootstrap
  pkg = 'bootstrap'
  esm_rel = 'dist/js/bootstrap.esm.min.js'
  node_path = 'node_modules/bootstrap/'
  src = File.join(node_path, esm_rel)

  installed = false

  if command_available?("yarn")
    say "Installing #{pkg} via yarn...", :green
    system("yarn add #{pkg} --silent")
    installed = true if File.exist?(src)
  elsif command_available?("npm")
    say "Installing #{pkg} via npm...", :green
    system("npm install #{pkg} --silent")
    installed = true if File.exist?(src)
  else
    say "No yarn or npm detected; cannot install #{pkg} locally", :yellow
  end

  unless installed && File.exist?(src)
    say "Local installation of #{pkg} failed or ESM file not found: #{src}", :red
    return false
  end

  # Copy into app/assets/javascripts so Rails can serve it under /assets/
  dest_dir = File.join('app', 'assets', 'javascripts')
  dest_file = File.join(dest_dir, 'bootstrap.esm.min.js')
  FileUtils.mkdir_p(dest_dir)
  FileUtils.cp(src, dest_file)

  say "Copied bootstrap ESM to #{dest_file}", :green

  # Ensure importmap file exists and pin locally
  importmap_file = 'config/importmap.rb'
  unless File.exist?(importmap_file)
    append_to_file importmap_file, "# Importmap mappings\n"
  end

  content = File.read(importmap_file)
  pin_line = %Q{pin "bootstrap", to: "/assets/bootstrap.esm.min.js"}

  unless content.include?(pin_line)
    append_to_file importmap_file, "\n#{pin_line}\n"
    say "Added local pin for bootstrap in #{importmap_file}", :green
  else
    say "Local pin for bootstrap already present in #{importmap_file}", :green
  end

  true
end
