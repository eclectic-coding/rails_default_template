require "fileutils"
require "shellwords"

def add_template_to_source_path
  source_paths.unshift(File.dirname(__FILE__))
end

def add_gems
  gem "faker", "~> 2.18"
  gem "bcrypt"

  gem_group :development, :test do
    gem "standard", "~> 1.1", ">= 1.1.5", require: false
    gem "capybara"
    gem "webdrivers"
  end

  gem_group :development do
    gem "fuubar", "~> 2.5", ">= 2.5.1"
    gem "guard", "~> 2.17"
    gem "guard-rspec", "~> 4.7", ">= 4.7.3"
    gem "rubocop", "~> 1.18"
    gem "rubocop-rails", "~> 2.11", ">= 2.11.3", require: false
    gem "rubocop-rspec", "~> 2.4"
    gem "factory_bot_rails", "~> 6.2"
  end

  gem_group :test do
    gem "simplecov", "~> 0.21.2", require: false
    gem "rspec-rails", "~> 5.0", ">= 5.0.1"
  end

  # gem_group :production do
  #   gem "pg"
  # end

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
  copy_file "Guardfile"
  copy_file "Procfile"
  copy_file "renovate.json"

  directory "app", force: true
  directory "config", force: true
  directory "db", force: true
  directory "lib", force: true
  directory "spec", force: true

  environment "config.action_mailer.default_url_options = { host: 'localhost', port: 3000 }", env: "development"
  environment "config.action_mailer.default_url_options = { host: 'example.com' }", env: "test"
end

def database_setup
  rails_command("db:create")
  rails_command("db:migrate")
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
  copy_templates
  config_generators
  add_static
  database_setup
  lint_code
  initial_commit

  say
  say "Rails app successfully created!", :blue
  say
  say "To get started with your new app:", :green
  say "  cd #{app_name}"
end
