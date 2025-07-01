# Airtable-Loops Field Integrator

## Commands
- **Development:** `docker compose run web rails server`
- **Console:** `docker compose run web rails console`
- **Test:** `docker compose run web rails test` (no tests written yet)
- **Lint:** `docker compose run web bundle exec rubocop`
- **Security:** `docker compose run web bundle exec brakeman`
- **Database:** `docker compose run web rails db:migrate`

## Architecture
Rails 8.0 app integrating Airtable webhooks with Loops.so email platform. Uses PostgreSQL with Good Job for background processing.

**Models:** `Webhook` (manages Airtable subscriptions), `Payload` (stores webhook data)
**Controllers:** `Airtable::WebhooksController` (receives webhooks), `Api::AddressController` (AI address parsing)
**Jobs:** Background processing via Good Job for async webhook handling
**Services:** Integration with Airtable API and Loops SDK

## Code Style
- **Linting:** Uses `rubocop-rails-omakase` (Standard Rails styling)
- **Format:** Standard Ruby/Rails conventions
- **Naming:** Snake_case for methods/variables, PascalCase for classes
- **Dependencies:** HTTPX for HTTP requests, Loops SDK for email integration
- **Structure:** Standard Rails MVC with services layer for business logic
