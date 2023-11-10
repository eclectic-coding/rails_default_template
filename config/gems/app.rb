gem "bcrypt"

group :development, :test do
  gem "standard", "~> 1.24", require: false
  gem "faker"
end

group :development do
  gem "rubocop"
  gem "rubocop-rails", require: false
end

group :test do
  gem "simplecov", "~> 0.21.2", require: false
end