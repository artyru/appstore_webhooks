# frozen_string_literal: true

module AppstoreWebhooks
  module Routes
    DEFAULT_PATH = 'appstore_webhooks'
    DEFAULT_CONTROLLER = '/appstore_webhooks/webhooks#create'

    def appstore_webhooks_notifications(path: DEFAULT_PATH, to: DEFAULT_CONTROLLER)
      options = to == DEFAULT_CONTROLLER ? { to: to, module: nil } : { to: to }
      post(path, **options)
    end
  end
end

ActionDispatch::Routing::Mapper.include(AppstoreWebhooks::Routes)
