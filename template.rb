require "fileutils"
require "shellwords"

def add_template_to_source_path
  source_paths.unshift(File.dirname(__FILE__))
end

def add_gems
  inject_into_file "Gemfile", after: "source \"https://rubygems.org\"" do
    "\n\neval_gemfile 'config/gems/app.rb'"
  end

  if options[:skip_test]
    inject_into_file "Gemfile", after: "eval_gemfile 'config/gems/app.rb'" do
      "\neval_gemfile 'config/gems/rspec_gemfile.rb'"
    end
  end

  directory "config/gems", force: true
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
  response = ask("Would you like to install a style system: bootstrap/tailwind/postcss/sass system? (b/t/p/s)", :green)

  add_javascript

  if response == "b"
    add_bootstrap
  elsif response == "t"
    add_tailwind
  elsif response == "p"
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
  add_esbuild_script

  # add flowbite
  # directory "app_tailwind", "app", force: true
  # TODO: finish tailwind views
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
  copy_file ".gitignore", force: true
  copy_file "esbuild.config.mjs", force: true
  copy_file ".rubocop.yml", force: true
  copy_file ".rubocop_todo.yml", force: true
  copy_file "Brewfile"

  directory "bin", force: true
  directory "lib", force: true

  environment "config.action_mailer.default_url_options = { host: 'localhost', port: 3000 }", env: "development"
  environment "config.action_mailer.default_url_options = { host: 'example.com' }", env: "test"
end

def setup_rspec
  return unless options[:skip_test]

  gsub_file "bin/ci", "bin/rails test", "bin/rspec"

  copy_file ".rspec"
  directory "spec", force: true
end

def database_setup
  remove_file "config/database.yml"
  rails_command("db:system:change --to=postgresql")
  rails_command("db:create")
  rails_command("db:migrate")
end

def command_available?(command)
  system("command -v #{command} >/dev/null 2>&1")
end

def run_setup
  # Install system dependencies if Homebrew is installed
  if command_available?("brew")
    system("brew bundle check --no-lock --no-upgrade") || system!("brew bundle --no-upgrade --no-lock")
  end
end

def local_ssl
  response = ask("Would you like to configure SSL for local development: (y/n)", :green)

  return unless response == "y"

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
  run "bundle binstub rspec-core" if options[:skip_test]
end

def lint_code
  run "bundle exec rubocop -a"
end

def initial_commit
  run "git init"
  run "git add . && git commit -m \"Initial_commit\""
end

# Main setup
add_template_to_source_path

add_gems

after_bundle do
  setup_styling
  copy_templates
  config_generators
  add_static
  setup_rspec
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
