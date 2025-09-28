# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in appstore_webhooks.gemspec
gemspec

gem "irb"
gem "rake", "~> 13.0"

gem "rubocop", "~> 1.21"

local_sdk_path = File.expand_path('../appstore_sdk', __dir__)
if Dir.exist?(local_sdk_path)
  gem "appstore_sdk", path: local_sdk_path
end

group :development, :test do
  gem "sqlite3"
end
