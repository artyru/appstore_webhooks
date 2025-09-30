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
# Add --skip-pundit if you do not use Pundit
# rails generate appstore_webhooks:install --skip-pundit
```

This copies:
- `config/initializers/appstore_webhooks.rb`
- `config/appstore_webhooks_entitlements.yml`
- migrations for notifications/subscriptions/subscription events
- `app/policies/dictionary_word_policy.rb` (skip with `--skip-pundit`)

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

Entitlements are controlled via `config/appstore_webhooks_entitlements.yml`:

```yaml
default: &default
  features:
    dictionary_words:
      product_ids:
        - pro.weekly
        - pro.monthly

development:
  <<: *default
```

Each feature maps to the App Store product IDs that unlock it and may optionally specify `allowed_statuses`.

Ensure the base `appstore_sdk` gem is also configured (bundle ID, keys, verify toggle). The engine automatically subscribes to webhook notifications and enqueues `ProcessNotificationWorker`.

## Configuration options

```ruby
AppstoreWebhooks.configure do |config|
  config.user_class = 'User'
  config.user_token_column = :app_account_token
  config.alert_email = ENV['APPSTORE_ALERT_EMAIL']
  config.consumption_builder = 'AppstoreWebhooks::ConsumptionRequestBuilder'
  config.entitlements = Rails.application.config_for(:appstore_webhooks_entitlements)
end
```

Override defaults as needed (e.g., if you store the token in another column, want a custom consumption builder, or prefer to build the entitlements hash inline).

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

### Maintenance tasks

Use the provided rake task to requeue failed notifications and run the processor again:

```bash
bundle exec rake appstore_webhooks:notifications:retry_failed
```

Optional environment variables:
- `LIMIT=<n>` — only requeue the first `n` failed notifications.
- `SILENT=true` — suppress the summary output.

Failed notifications without stored raw payloads are skipped to avoid enqueuing malformed jobs.

### Remote subscription synchronisation

The `RemoteSubscriptionSyncService` provides on-demand refresh of subscription state via the App Store Server API. Internally it maps Apple’s `SubscriptionStatus` values to the engine’s enum using the following table:

| Apple status                | Local status       |
|----------------------------|--------------------|
| `ACTIVE`                   | `active`
| `IN_GRACE_PERIOD`          | `grace`
| `BILLING_GRACE_PERIOD`     | `grace`
| `BILLING_RETRY`            | `billing_retry`
| `EXPIRED`                  | `expired`
| `REVOKED`                  | `revoked`

Any status not present in the table leaves the local status unchanged. The service will also:
- Fetch `getAllSubscriptionStatuses` and `getTransactionHistory` for a transaction id.
- Decode signed transactions/renewal info using the app’s configured verifier.
- Update `Subscription` timestamps, product, token, environment, auto-renew flag, and any mapped status.
- Skip updates when the payload is older than `subscription.last_synced_at`, logging a stale event.
- Always touch `last_synced_at` so periodic jobs can use it as a freshness guard.

Two rake tasks wrap the job:

```bash
bundle exec rake appstore_webhooks:subscriptions:sync[ORIGINAL_ID]
# or async: ASYNC=true bundle exec rake appstore_webhooks:subscriptions:sync[ORIGINAL_ID]

bundle exec rake appstore_webhooks:subscriptions:sync_stale
# supports LIMIT, BATCH_SIZE, STALE_AFTER_MINUTES, ASYNC, SILENT
```

The tasks enqueue `SyncSubscriptionJob`, which in turn runs `RemoteSubscriptionSyncService`.

## Development

1. Run the test suite for the gem (`bundle exec rake test`) using the provided in-memory harness.
2. In the host application, run the full test suite to ensure integration is wired correctly.

## License

TODO: Specify license if needed.
