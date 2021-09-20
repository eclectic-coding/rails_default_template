source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby "3.0.1"

gem "rails", "~> 6.1.4"
gem "puma", "~> 5.0"
gem "sass-rails", ">= 6"
gem "webpacker", "~> 5.0"
gem "turbolinks", "~> 5"
gem "jbuilder", "~> 2.7"
gem "bootsnap", ">= 1.4.4", require: false
# ===== App specific gems  ==========================
gem "name_of_person"
gem "friendly_id"

group :development, :test do
  gem "byebug", platforms: [:mri, :mingw, :x64_mingw]
  gem "sqlite3", "~> 1.4"
  # ===== App specific gems  ==========================
  gem "faker", "~> 2.18"
  gem "standard", "~> 1.1", ">= 1.1.2", require: false
  gem "rspec-rails", "~> 5.0", ">= 5.0.1"
  gem "factory_bot_rails", "~> 6.2"
  gem "capybara"
  gem "webdrivers"
end

group :development do
  gem "web-console", ">= 4.1.0"
  gem "rack-mini-profiler", "~> 2.0"
  gem "listen", "~> 3.3"
  gem "spring"
  # ===== App specific gems  ==========================
  gem "fuubar", "~> 2.5", ">= 2.5.1"
  gem "guard", "~> 2.17"
  gem "guard-rspec", "~> 4.7", ">= 4.7.3"
  gem "guard-livereload", "~> 2.5", ">= 2.5.2", require: false
  gem "rubocop", "~> 1.17"
  gem "rubocop-rails", "~> 2.11", ">= 2.11.1", require: false
  gem "rubocop-rspec", "~> 2.4"
end

# ===== App specific gems  ==========================
group :test do
  gem "rexml", "~> 3.2", ">= 3.2.5" # Just for outstanding bug
  gem "simplecov", "~> 0.21.2", require: false
end

group :production do
  gem "pg", "~> 1.2", ">= 1.2.3" # For Heroku deploy
end

gem "tzinfo-data", platforms: [:mingw, :mswin, :x64_mingw, :jruby]

