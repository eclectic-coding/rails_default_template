gem "bcrypt"
gem "cssbundling-rails"

group :development, :test do
  gem "faker"
end

group :development do
  gem "rubocop-rails-omakase", require: false
end

group :test do
  gem "simplecov", "~> 0.21.2", require: false
  gem "test-prof"
end