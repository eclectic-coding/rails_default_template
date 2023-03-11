gem "bcrypt"

group :development, :test do
  gem "standard", "~> 1.9", require: false
  gem "capybara"
  gem "webdrivers"
  gem "rspec-rails", "~> 6.0.0"
  gem "factory_bot_rails"
  gem "faker"
end

group :development do
  gem "fuubar", "~> 2.5", ">= 2.5.1"
  gem "guard"
  gem "guard-rspec"
  gem "rubocop"
  gem "rubocop-rails", require: false
  gem "rubocop-rspec"
end

group :test do
  gem "simplecov", "~> 0.21.2", require: false
end