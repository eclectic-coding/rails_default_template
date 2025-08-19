group :development, :test do
  gem 'rspec-rails', '~> 8.0.0'
  gem "factory_bot_rails"
end

group :development do
  gem "fuubar"
end

group :test do
  gem "webmock"
  gem 'simplecov', '~> 0.22.0', require: false
  gem "test-prof"
end
