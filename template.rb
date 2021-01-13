require "fileutils"
require "shellwords"

def add_template_repository_to_source_path
  source_paths.unshift(File.dirname(__FILE__))
end

def add_gems
  gem_group :development, :test do
    gem "capybara", ">= 2.15"
    gem "database_cleaner"
    gem "factory_bot_rails", git: "http://github.com/thoughtbot/factory_bot_rails"
    gem "rspec-rails"
  end

  gem_group :development do
    gem "fuubar"
    gem "guard"
    gem "guard-rspec"
    gem "rubocop"
    gem "rubocop-rails", require: false
    gem "rubocop-rspec"
  end

  gem_group :test do
    gem "simplecov", require: false
  end

end

def set_application_name
  environment "config.application_name = Rails.application.class.module_parent_name"
end

def add_static
  generate "controller static home"

  route "root to: 'static#home'"
end

def testing_setup
  generate "rspec:install"
end

def copy_templates
  remove_dir "spec"

  copy_file "Guardfile"
  copy_file ".rspec", force: true
  copy_file ".rubocop.yml"
  copy_file ".simplecov"

  directory "lib", force: true
  directory "spec", force: true
end

def stop_spring
  run "spring stop"
end

def database_setup
  rails_command("db:create")
  rails_command("db:migrate")
end

# Main setup
add_template_repository_to_source_path

add_gems

after_bundle do
  set_application_name
  stop_spring
  add_static
  # testing_setup
  copy_templates
  database_setup

  say
  say "Rails Article app successfully created!", :blue
  say
  say "To get started with your new app:", :green
  say "  cd #{app_name}"
end
