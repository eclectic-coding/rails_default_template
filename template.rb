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
  gem "faker"

  gem_group :development, :test do
    gem "standard", require: false
    gem "rspec-rails"
    gem "factory_bot_rails"
    gem "capybara"
    gem "webdrivers"
  end

  gem_group :development do
    gem "fuubar"
    gem "guard"
    gem "guard-rspec"
    gem "guard-livereload", "~> 2.5", require: false
    gem "rubocop"
    gem "rubocop-rails", require: false
    gem "rubocop-rspec"
  end

  gem_group :test do
    gem "rexml" # Added to fix error until selenium-webdriver updated to v.4
    gem "simplecov", require: false
  end

  gem_group :production do
    gem "pg"
  end

end

def set_application_name
  environment "config.application_name = Rails.application.class.module_parent_name"
end

def config_generators
  initializer "generators.rb", <<-CODE
    Rails.application.config.generators do |g|
      g.test_framework :rspec,
        fixtures:         false,
        view_specs:       false,
        helper_specs:     false,
        routing_specs:    false,
        request_specs:    false,
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

def pack_styles
  inject_into_file "app/views/layouts/application.html.erb", before: "</head>" do
    <<-EOF
      <%= stylesheet_pack_tag 'application', media: 'all', 'data-turbolinks-track': 'reload' %>
    EOF
  end

  inject_into_file "app/javascript/packs/application.js", after: "ActiveStorage.start()\n" do
    <<-EOF
        import "../stylesheets/application.scss"
    EOF
  end
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
  pack_styles
  add_static
  database_setup
  lint_code
  initial_commit

  say
  say "Rails Article app successfully created!", :blue
  say
  say "To get started with your new app:", :green
  say "  cd #{app_name}"
end
