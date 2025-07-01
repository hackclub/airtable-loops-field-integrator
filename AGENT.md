# Agent Instructions

## Commands

**Docker Compose**: Use `docker compose run --rm web COMMAND` for all Rails commands.

**Testing**: 
- Boot test: `docker compose run --rm --no-deps web rails runner "puts 'Rails app boots successfully'"`
- Full test: `docker compose run --rm web rails runner "puts 'All good'"`

**Deployment**: The app runs in production, so test thoroughly before pushing changes.

## Notes

- Rails 8 requires different authentication syntax than previous versions
- Use `before_action :authenticate` with `authenticate_or_request_with_http_basic` instead of `http_basic_authenticate_with` with lambdas
