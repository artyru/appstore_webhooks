# AppstoreWebhooks

Rails engine that layers domain logic (persistence, state machine, alerting, consumption responses) on top of the [appstore_sdk](https://github.com/artyru/appstore_sdk) decoder. It provides:

- ActiveRecord models (`Notification`, `Subscription`, `SubscriptionEvent`).
- AASM-powered subscription state transitions via `SubscriptionSyncService`.
- Background workers/jobs to process ASSN payloads and respond to consumption requests.
- Alert mailer for missing `app_account_token` users.
- Consumption request builder/service for the StoreKit "Send Consumption Information" API.
- Install generator to copy migrations and configuration into your app.

## Installation

Add the gem to your application:

```ruby
# Gemfile
gem 'appstore_webhooks', git: 'https://github.com/your-org/appstore_webhooks' # or path: 'appstore_webhooks'
```

Run bundler and the install generator:

```bash
bundle install
rails generate appstore_webhooks:install
rails db:migrate
```

This copies:
- `config/initializers/appstore_webhooks.rb`
- migrations for notifications/subscriptions/subscription events

### Test utilities

Run the setup generator to scaffold FactoryBot fixtures and helpers in the host app:

```bash
rails generate appstore_webhooks:setup
```

The generator detects whether you keep tests under `spec/` (RSpec) or `test/` (Minitest) and will create:
- `spec|test/factories/appstore_webhooks/*` with factories mirroring the engine models and Apple payload fixtures.
- `spec|test/support/appstore_webhooks_payload_helper.rb` with the `encode_apple_jws` helper mixed into the appropriate test framework.

Need an example request spec? Append `--with-request-spec` to copy a template that posts a signed payload to the webhook endpoint:

```bash
rails generate appstore_webhooks:setup --with-request-spec
```

Tweak the generated file to match your route, authentication, and user factory naming.

Configure any options in the initializer (e.g. `user_class`, `user_token_column`, `alert_email`).

Ensure the base `appstore_sdk` gem is also configured (bundle ID, keys, verify toggle). The engine automatically subscribes to webhook notifications and enqueues `ProcessNotificationWorker`.

## Configuration options

```ruby
AppstoreWebhooks.configure do |config|
  config.user_class = 'User'
  config.user_token_column = :app_account_token
  config.alert_email = ENV['APPSTORE_ALERT_EMAIL']
  config.consumption_builder = 'AppstoreWebhooks::ConsumptionRequestBuilder'
end
```

Override defaults as needed (e.g., if you store the token in another column or want a custom consumption builder).

## Usage in host app

- Keep your existing webhook route (e.g., `/api/v1/appstore_sdk`), pointing to `appstore_sdk` controller from the base gem.
- Remove local copies of subscription models/workers/mailer; instead, subclass the provided ones if you need additional behaviour:

```ruby
# app/models/subscription.rb
class Subscription < AppstoreWebhooks::Subscription
end
```

```ruby
# app/workers/appstore_sdk/process_notification_worker.rb
module AppstoreWebhooks
  class ProcessNotificationWorker < AppstoreWebhooks::ProcessNotificationWorker
  end
end
```

- The engine handles everything else: decoding payloads, persisting notifications/subscriptions, updating state machine, sending consumption info, and emailing alerts on missing users.

## Development

1. Run the test suite for the gem (`bundle exec rake test`) using the provided in-memory harness.
2. In the host application, run the full test suite to ensure integration is wired correctly.

## License

TODO: Specify license if needed.
