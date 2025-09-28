# frozen_string_literal: true

require 'bundler/setup'
ENV['RAILS_ENV'] ||= 'test'
ENV['DATABASE_URL'] ||= 'sqlite3::memory:'

require 'rails'
require 'active_record/railtie'
require 'active_job/railtie'
require 'action_controller/railtie'
require 'action_mailer/railtie'
require 'action_view/railtie'

require 'minitest/autorun'
require 'securerandom'
require 'json'
require 'rack/mock'
require 'rack/utils'
require 'logger'
require 'base64'
require 'active_job/test_helper'
require 'active_support/testing/time_helpers'

module TestApp
  class Application < Rails::Application
    config.load_defaults 7.1 if config.respond_to?(:load_defaults)
    config.eager_load = false
    config.root = File.expand_path('..', __dir__)
    config.logger = Logger.new($stdout)
    config.logger.level = Logger::FATAL
    config.active_support.test_order = :random
    config.active_job.queue_adapter = :test
    config.action_mailer.delivery_method = :test
    config.action_mailer.perform_deliveries = true
    config.secret_key_base = 'test-secret-key'
    config.hosts.clear if config.respond_to?(:hosts)
  end
end

Rails.application = TestApp::Application.new unless defined?(Rails.application) && Rails.application
Rails.application.initialize!

ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
ActiveRecord::Base.logger = nil
ActiveRecord::Migration.verbose = false

ActiveRecord::Schema.define do
  create_table :users, force: true do |t|
    t.string :app_account_token, null: false
    t.string :apple_uid
    t.timestamps
  end

  create_table :subscriptions, force: true do |t|
    t.references :user, null: false
    t.string :original_transaction_id, null: false
    t.string :app_account_token, null: false
    t.string :product_id
    t.string :status, null: false, default: 'active'
    t.boolean :auto_renew_status
    t.datetime :expires_at
    t.datetime :grace_period_expires_at
    t.datetime :last_synced_at
    t.string :environment, null: false, default: 'sandbox'
    t.timestamps
  end
  add_index :subscriptions, :original_transaction_id, unique: true
  add_index :subscriptions, :app_account_token

  create_table :appstore_webhook_notifications, force: true do |t|
    t.string :notification_type, null: false
    t.string :subtype
    t.string :notification_uuid, null: false
    t.string :app_account_token
    t.json :raw_payload, null: false, default: {}
    t.json :transaction_payload, null: false, default: {}
    t.json :renewal_payload, null: false, default: {}
    t.string :processing_state, null: false, default: 'pending'
    t.string :processing_error
    t.references :subscription
    t.timestamps
  end
  add_index :appstore_webhook_notifications, :notification_uuid, unique: true
  add_index :appstore_webhook_notifications, :processing_state

  create_table :subscription_events, force: true do |t|
    t.references :subscription, null: false
    t.references :webhook_notification, null: false
    t.string :previous_status
    t.string :next_status, null: false
    t.datetime :effective_at, null: false
    t.json :metadata, null: false, default: {}
    t.timestamps
  end
  add_index :subscription_events, :effective_at
end

class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end

class ApplicationJob < ActiveJob::Base
end

class ApplicationMailer < ActionMailer::Base
  default from: 'alerts@example.com'
  layout nil
end

class User < ApplicationRecord
end

require 'appstore_webhooks'

AppstoreWebhooks.configure do |config|
  config.user_class = 'User'
  config.alert_email = 'alerts@example.com'
  config.enable_online_checks = false
  config.verification_enabled = false
end

AppstoreSDK.configure do |config|
  config.environment = :local_testing
  config.bundle_id = 'team.memriq.test'
  config.enable_online_checks = false
  config.verification_enabled = false
end

ActiveJob::Base.queue_adapter = :test
ActionMailer::Base.deliveries.clear
Time.zone = 'UTC'

Dir[File.join(__dir__, 'support/**/*.rb')].sort.each { |file| require file }

module TestHelpers
  module Factory
    def create_user(attrs = {})
      defaults = {
        app_account_token: SecureRandom.uuid,
        apple_uid: SecureRandom.uuid
      }
      User.create!(defaults.merge(attrs))
    end

    def create_subscription(attrs = {})
      user = attrs[:user] || create_user
      defaults = {
        user: user,
        original_transaction_id: SecureRandom.uuid,
        app_account_token: attrs[:app_account_token] || user.app_account_token,
        product_id: 'product.basic',
        status: 'active',
        environment: 'sandbox'
      }
      AppstoreWebhooks::Subscription.create!(defaults.merge(attrs))
    end

    def create_notification(attrs = {})
      subscription = attrs[:subscription]
      defaults = {
        notification_uuid: SecureRandom.uuid,
        notification_type: 'SUBSCRIBED',
        app_account_token: subscription&.app_account_token || SecureRandom.uuid,
        raw_payload: {},
        transaction_payload: {},
        renewal_payload: {},
        processing_state: 'pending',
        subscription: subscription
      }
      AppstoreWebhooks::Notification.create!(defaults.merge(attrs))
    end

    def create_subscription_event(attrs = {})
      subscription = attrs[:subscription] || create_subscription
      notification = attrs[:webhook_notification] || create_notification(subscription: subscription)
      defaults = {
        subscription: subscription,
        webhook_notification: notification,
        previous_status: 'active',
        next_status: 'canceled',
        effective_at: Time.current,
        metadata: {}
      }
      AppstoreWebhooks::SubscriptionEvent.create!(defaults.merge(attrs))
    end

    def build_transaction_payload(overrides = {})
      {
        'bundleId' => 'team.memriq.test',
        'appAccountToken' => SecureRandom.uuid,
        'originalTransactionId' => SecureRandom.uuid,
        'transactionId' => SecureRandom.uuid,
        'productId' => 'product.basic',
        'environment' => 'LocalTesting',
        'expiresDate' => (Time.current + 1.day).to_i * 1000
      }.merge(overrides.transform_keys(&:to_s))
    end

    def build_renewal_payload(overrides = {})
      {
        'originalTransactionId' => SecureRandom.uuid,
        'autoRenewStatus' => '1',
        'environment' => 'LocalTesting'
      }.merge(overrides.transform_keys(&:to_s))
    end
  end
end

module AppleWebhookPayloadHelper
  def encode_apple_jws(payload)
    header = Base64.urlsafe_encode64({ alg: 'none', kid: nil, typ: 'JWT' }.to_json, padding: false)
    body   = Base64.urlsafe_encode64(payload.to_json, padding: false)
    [header, body, ''].join('.')
  end
end

ActiveSupport::TestCase.include(TestHelpers::Factory)
ActiveSupport::TestCase.include(AppleWebhookPayloadHelper)
ActiveSupport::TestCase.include(ActiveJob::TestHelper)
ActiveSupport::TestCase.include(ActiveSupport::Testing::TimeHelpers)
ActiveSupport::TestCase.include(ActiveRecord::TestFixtures)
ActiveSupport::TestCase.test_order = :random
ActiveSupport::TestCase.use_transactional_tests = true if ActiveSupport::TestCase.respond_to?(:use_transactional_tests=)

module AppstoreWebhooks
  class WebhooksController
    class_attribute :test_processor, instance_accessor: false, default: nil

    private

    def processor
      self.class.test_processor || super
    end
  end
end
