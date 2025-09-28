# frozen_string_literal: true

require 'test_helper'

class AppstoreWebhooksRoutesTest < ActiveSupport::TestCase
  class FakeMapper
    include AppstoreWebhooks::Routes

    attr_reader :calls

    def initialize
      @calls = []
    end

    def post(path, **options)
      @calls << [path, options]
    end
  end

  def setup
    @mapper = FakeMapper.new
  end

  def test_default_route_configuration
    @mapper.appstore_webhooks_notifications

    path, options = @mapper.calls.first
    assert_equal 'appstore_webhooks', path
    assert_equal({ to: '/appstore_webhooks/webhooks#create', module: nil }, options)
  end

  def test_custom_route_configuration
    @mapper.appstore_webhooks_notifications(path: 'storekit/notifications', to: 'api/webhooks#create')

    path, options = @mapper.calls.first
    assert_equal 'storekit/notifications', path
    assert_equal({ to: 'api/webhooks#create' }, options)
  end
end
