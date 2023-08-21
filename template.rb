require "fileutils"
require "shellwords"

def add_template_to_source_path
  source_paths.unshift(File.dirname(__FILE__))
end

def add_gems
  inject_into_file "Gemfile", "gem \"cssbundling-rails\"\n", after: "gem \"jsbundling-rails\"\n"

  append_to_file "Gemfile" do
    "eval_gemfile 'config/gems/app.rb'\n"
  end

  directory "config", force: true
end

def add_javascript
  run "yarn add chokidar -D"
end

def add_bootstrap
  rails_command "css:install:bootstrap"
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
  # Jason Swett: "The Complete Guide to Rails Testing"
  initializer "generators.rb", <<-CODE
    Rails.application.config.generators do |g|
      g.test_framework :rspec,
        view_specs:       false,
        helper_specs:     false,
        routing_specs:    false
    end
  CODE
  inject_into_file "config/application.rb", "    config.generators.helper = false", after: "config.generators.system_tests = nil\n"
  inject_into_file "config/application.rb", "    config.generators.stylesheets = false\n\n", after: "config.generators.helper = false\n"
end

def add_static
  generate "controller static home"

  route "root to: 'static#home'"
end

def copy_templates
  copy_file ".gitignore", force: true
  copy_file ".rspec", force: true
  copy_file ".rubocop.yml"
  copy_file ".rubocop_rails.yml"
  copy_file ".rubocop_rspec.yml"
  copy_file ".rubocop_strict.yml"
  copy_file ".rubocop_todo.yml"
  copy_file ".simplecov"
  copy_file "esbuild.config.mjs"
  copy_file "Guardfile"
  copy_file "Procfile.dev", force: true

  directory "app", force: true
  directory "lib", force: true
  directory "spec", force: true

  environment "config.action_mailer.default_url_options = { host: 'localhost', port: 3000 }", env: "development"
  environment "config.action_mailer.default_url_options = { host: 'example.com' }", env: "test"
end

def database_setup
  rails_command("db:create")
  rails_command("db:migrate")
end

def add_binstubs
  run "bundle binstub rspec-core"
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
  copy_templates
  add_esbuild_script
  config_generators
  add_bootstrap
  add_static
  database_setup
  add_binstubs
  lint_code
  initial_commit

  say
  say "Rails app successfully created!", :blue
  say
  say "To get started with your new app:", :green
  say "  cd #{app_name}"
end
