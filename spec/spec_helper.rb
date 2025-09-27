# frozen_string_literal: true

require 'bundler/setup'
require 'appstore_webhooks'
require 'rspec/rails'

ENGINE_ROOT = File.expand_path('..', __dir__)
TMP_ROOT    = File.join(ENGINE_ROOT, 'tmp')

Dir.mkdir(TMP_ROOT) unless Dir.exist?(TMP_ROOT)
ENV['RAILS_ENV'] ||= 'test'

dummy_env = File.expand_path('dummy/config/environment', __dir__)
host_env = File.expand_path('../../config/environment', __dir__)

if File.exist?("#{dummy_env}.rb")
  require dummy_env
elsif File.exist?(host_env)
  require host_env
else
  raise "Unable to locate Rails environment for specs. Expected #{dummy_env}.rb or #{host_env}."
end

Dir[File.join(__dir__, 'support/**/*.rb')].sort.each { |file| require file }

RSpec.configure do |config|
  config.example_status_persistence_file_path = '.rspec_status'
  config.disable_monkey_patching!

  config.use_transactional_fixtures = true
  config.before(:suite) do
    ActiveRecord::Migration.maintain_test_schema!
  end

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
