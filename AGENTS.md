# Repository Guidelines

## Project Structure & Module Organization
- `lib/appstore_webhooks` holds the engine entry point and integration glue for host apps.
- `app/` mirrors standard Rails domains (`controllers`, `models`, `services`, `workers`, etc.) and should stay slim, delegating cross-cutting logic to `lib/`.
- `test/` groups Minitest cases (`models/`, `services/`, `jobs/`, `workers/`, etc.) plus support helpers in `test/test_helper.rb`.
- `sig/` contains RBI signatures; update them when you change public APIs.
- Generated binstubs live in `bin/`; prefer checking in new binstubs when adding tooling.

## Build, Test, and Development Commands
- `bundle install` — install gem dependencies.
- `bundle exec rake test` — run the Minitest suite.
- `bundle exec rubocop` — apply the enforced style and lint rules.
- `bundle exec rake` — run the default pipeline (test + rubocop); use this before opening a PR.
- `bundle exec rake build` — package the engine gem; run when validating releases.

## Coding Style & Naming Conventions
- Follow the project `.rubocop.yml`; default Ruby style applies (two-space indentation, UTF-8 source, frozen string literals).
- Classes and modules use `CamelCase`; files, database tables, and specs use `snake_case`.
- Extract shared logic to service objects or `lib/` modules; keep controllers and workers thin.
- When adding CLI scripts, create a binstub and require the top-level `appstore_webhooks` entrypoint.

## Testing Guidelines
- Use Minitest with descriptive method names (`test_handles_expired_subscription`). Mirror the runtime directory when adding cases.
- Keep shared helpers in `test/test_helper.rb` and load automatically; prefer lightweight factory helpers over complex fixtures.
- Add regression tests for every observable change; leverage `ActiveJob::TestHelper` when asserting async flows.
- Run `bundle exec rake test` and ensure the default `bundle exec rake` passes before pushing.

## Commit & Pull Request Guidelines
- Write imperative, scoped commit subjects (“Add renewal event mapper”); wrap at ~72 characters.
- Squash fixups locally; each commit should pass `bundle exec rake`.
- Describe observable changes in the PR body, link related issues, and include screenshots or sample payloads when UI/API behavior shifts.
- State how you validated the change (commands run, sample webhook payloads) so reviewers can reproduce quickly.
