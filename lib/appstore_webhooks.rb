# frozen_string_literal: true

require "rails"
require "appstore_sdk"
require "aasm"

require_relative "appstore_webhooks/version"
require_relative "appstore_webhooks/configuration"
require_relative "appstore_webhooks/engine"
require_relative "appstore_webhooks/routes"

module AppstoreWebhooks
  class Error < StandardError; end

  class << self
    attr_writer :configuration

    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end
  end
end
