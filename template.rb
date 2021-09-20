require "fileutils"
require "shellwords"

def add_template_repository_to_source_path
  if __FILE__ =~ %r{\Ahttps?://}
    require "tmpdir"
    source_paths.unshift(tempdir = Dir.mktmpdir("rails_default_template"))
    at_exit { FileUtils.remove_entry(tempdir) }
    git clone: [
      "--quiet",
      "https://github.com/eclectic-coding/rails_default_template.git",
      tempdir
    ].map(&:shellescape).join(" ")

    if (branch = __FILE__[%r{rails_default_template/(.+)/template.rb}, 1])
      Dir.chdir(tempdir) { git checkout: branch }
    end
  else
    source_paths.unshift(File.dirname(__FILE__))
  end
end

def add_gems
  gem "faker", "~> 2.18"
  gem "jsbundling-rails"
  gem "cssbundling-rails"

  gem_group :development, :test do
    gem "standard", "~> 1.1", ">= 1.1.5", require: false
    gem "rspec-rails", "~> 5.0", ">= 5.0.1"
    gem "factory_bot_rails", "~> 6.2"
    gem "capybara"
    gem "webdrivers"
  end

  gem_group :development do
    gem "fuubar", "~> 2.5", ">= 2.5.1"
    gem "guard", "~> 2.17"
    gem "guard-rspec", "~> 4.7", ">= 4.7.3"
    gem 'guard-livereload', '~> 2.5', '>= 2.5.2', require: false
    gem 'rubocop', '~> 1.18'
    gem "rubocop-rails", "~> 2.11", ">= 2.11.3", require: false
    gem "rubocop-rspec", "~> 2.4"
  end

  gem_group :test do
    gem "rexml", "~> 3.2", ">= 3.2.5" # Added to fix error until selenium-webdriver updated to v.4
    gem "simplecov", "~> 0.21.2", require: false
  end

  gem_group :production do
    gem "pg", "~> 1.2", ">= 1.2.3"
  end

end

def set_application_name
  environment "config.application_name = Rails.application.class.module_parent_name"
end

def config_generators
  # Jason Swett: "The Complete Guide to Rails Testing"
  initializer "generators.rb", <<-CODE
    Rails.application.config.generators do |g|
      g.test_framework :rspec,
        view_specs:       false,
        helper_specs:     false,
        routing_specs:    false,
        controller_specs: false
    end
  CODE
  inject_into_file "config/application.rb", "    config.generators.helper = false", after: "config.load_defaults 6.1\n"
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
  directory "spec", force: true
end

def build_javascript
  rails_command("javascript:install:esbuild")
end

def stop_spring
  run "spring stop"
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
add_template_repository_to_source_path

add_gems

after_bundle do
  set_application_name
  stop_spring
  copy_templates
  config_generators
  # pack_styles
  build_javascript
  add_static
  database_setup
  lint_code
  initial_commit

  say
  say "Rails app successfully created!", :blue
  say
  say "To build styles: rails css:install:[tailwind|bootstrap|bulma|postcss|sass]", :yellow
  say
  say "To get started with your new app:", :green
  say "  cd #{app_name}"
end
