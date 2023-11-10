require "fileutils"
require "shellwords"

def add_template_to_source_path
  source_paths.unshift(File.dirname(__FILE__))
end

def add_gems
  append_to_file "Gemfile" do
    "eval_gemfile 'config/gems/app.rb'\n"
  end

  directory "config", force: true
end

def add_javascript
  run "yarn add chokidar -D"
  run "yarn add esbuild-rails"

  run "echo | node -v | cut -c 2- > .node-version"
end

def add_esbuild_script
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

def config_generators
  inject_into_file "config/application.rb", "    config.generators.helper = false", after: "config.generators.system_tests = nil\n"
  inject_into_file "config/application.rb", "    config.generators.stylesheets = false\n\n", after: "config.generators.helper = false\n"
end

def add_static
  generate "controller static home"

  route "root to: 'static#home'"
end

def add_bootstrap
  rails_command "css:install:bootstrap"
end

def copy_templates
  copy_file ".gitignore", force: true
  copy_file ".rubocop.yml"
  copy_file ".rubocop_rails.yml"
  copy_file ".rubocop_strict.yml"
  copy_file ".rubocop_todo.yml"
  copy_file "Brewfile"
  copy_file "esbuild.config.mjs"
  copy_file "Procfile.dev", force: true

  directory "app", force: true
  directory "bin", force: true
  directory "lib", force: true

  environment "config.action_mailer.default_url_options = { host: 'localhost', port: 3000 }", env: "development"
  environment "config.action_mailer.default_url_options = { host: 'example.com' }", env: "test"
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

def add_binstubs
  run "bundle binstub rubocop"
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
  add_javascript
  add_bootstrap
  copy_templates
  add_esbuild_script
  config_generators
  add_static
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
