group :development, :test do
end

group :development do
end

group :test do
  gem "webmock"
  gem "minitest-reporters"
  gem "simplecov", "~> 0.21.2", require: false
end
