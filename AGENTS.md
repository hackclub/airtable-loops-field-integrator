# AI Agent Development Environment Guide

This document describes the development environment setup and best practices for AI agents working on this Rails application.

## Quick Start Checklist

**Before making ANY changes, always:**

```bash
# 1. Check if containers are running
docker-compose ps

# 2. If web container is running, use it:
docker-compose exec web <your-command>

# 3. After code changes, restart if needed:
docker-compose exec web touch tmp/restart.txt

# 4. DO NOT rebuild unless Gemfile/Dockerfile changed!
```

## Development Workflows

This project uses Docker Compose for local development. There are two primary workflows:

### Workflow 1: Interactive Development (Recommended for AI Agents)

```bash
# Start only the dependencies (database and Redis)
docker-compose up -d db redis

# Start an interactive bash session in the web container with port forwarding
docker-compose run --service-ports web /bin/bash

# Inside the container, start the Rails server manually
rails s -b 0.0.0.0
```

This allows you to run commands interactively and manually control when the server starts/stops.

### Workflow 2: Automated Service Startup

```bash
# Start all services (web server starts automatically)
docker-compose up
```

This starts all services including the Rails server automatically.

## Code Reloading

Rails is configured for automatic code reloading in development:

- **Automatic reloading**: Rails automatically reloads code changes. No restart needed for most changes.
- **Manual restart trigger**: If you need to manually trigger a restart, touch the restart file:
  ```bash
  touch tmp/restart.txt
  ```
  This works because Puma has the `tmp_restart` plugin enabled.

## AI Agent Best Practices

### Before Making Changes

**ALWAYS check if a development server is already running:**

1. **Check for running containers:**
   ```bash
   docker-compose ps
   ```
   Look for a `web` service that shows as "Up" or "running"

2. **Check if port 3000 is in use:**
   ```bash
   lsof -i :3000
   # or
   netstat -tulpn | grep :3000
   ```

### If Server is Already Running

**DO NOT start a new container or server instance!**
**DO NOT rebuild Docker containers unless absolutely necessary!**

Instead:
1. Use the existing container:
   ```bash
   # Get the container name/ID
   docker-compose ps web
   
   # Execute commands in the existing container
   docker-compose exec web <command>
   ```

2. After making code changes, trigger a reload:
   ```bash
   docker-compose exec web touch tmp/restart.txt
   ```
   
   Or if you're in the same container, just:
   ```bash
   touch tmp/restart.txt
   ```

3. Most code changes auto-reload, but restart file is useful for:
   - Configuration changes
   - Initializer changes
   - Gem changes (though these may require a full restart)

**IMPORTANT: When to Rebuild Containers**

**ONLY rebuild Docker containers when:**
- Gemfile or Gemfile.lock changed (new gems added)
- Dockerfile changed
- Docker-compose.yml changed in ways that affect the build

**DO NOT rebuild for:**
- Application code changes (use `touch tmp/restart.txt`)
- Configuration file changes (use `touch tmp/restart.txt`)
- Database schema changes (run migrations in existing container)
- Most development work (code auto-reloads)

### If Server is NOT Running

1. Start dependencies first:
   ```bash
   docker-compose up -d db redis
   ```

2. Wait for services to be healthy:
   ```bash
   docker-compose ps  # Check db and redis are healthy
   ```

3. Start the web service:
   ```bash
   # Option A: Start with docker-compose (auto-starts server)
   docker-compose up web
   
   # Option B: Interactive mode (recommended for development)
   docker-compose run --service-ports web /bin/bash
   # Then inside: rails s -b 0.0.0.0
   ```

## Database Operations

When running database commands, use the existing container if available:

```bash
# If server is running
docker-compose exec web rails db:migrate
docker-compose exec web rails db:seed
docker-compose exec web rails console

# If server is not running
docker-compose run --rm web rails db:migrate
docker-compose run --rm web rails db:seed
docker-compose run --rm web rails console
```

## Common Commands

### Check Service Status
```bash
docker-compose ps
```

### View Logs
```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f web
docker-compose logs -f db
docker-compose logs -f redis
docker-compose logs -f sidekiq
```

### Stop Services
```bash
# Stop all services
docker-compose down

# Stop specific service
docker-compose stop web
```

### Rebuild After Changes (Only When Necessary!)

**Only rebuild when Gemfile, Dockerfile, or docker-compose.yml changes:**

```bash
# Rebuild images (ONLY after Gemfile/Dockerfile changes)
docker-compose build

# Rebuild and restart
docker-compose up --build
```

**For most code changes, just use the restart file:**
```bash
docker-compose exec web touch tmp/restart.txt
```

## Environment Variables

Key environment variables are set in `docker-compose.yml`:
- `DATABASE_URL`: PostgreSQL connection string
- `REDIS_URL`: Redis connection string  
- `RAILS_ENV`: Set to `development`

## Service Ports

- **Web server**: http://localhost:3000
- **PostgreSQL**: localhost:5432
- **Redis**: localhost:6379
- **Sidekiq**: Runs as a background service (no web UI by default)

## Troubleshooting

### Port Already in Use
If port 3000 is already in use:
1. Check what's using it: `lsof -i :3000`
2. Use the existing container, or stop the conflicting service

### Database Connection Issues
Ensure db service is healthy:
```bash
docker-compose ps db
# Should show "healthy" status
```

### Code Changes Not Reflecting
1. Check that Rails reloading is enabled (it is by default in development)
2. Try manual restart: `touch tmp/restart.txt`
3. Check for syntax errors in logs: `docker-compose logs web`

## Summary for AI Agents

**Before any development work:**
1. ✅ Check if server is running: `docker-compose ps`
2. ✅ If running: Use existing container with `docker-compose exec web`
3. ✅ If not running: Start with `docker-compose run --service-ports web /bin/bash`
4. ✅ After code changes: Most auto-reload; use `touch tmp/restart.txt` for config/initializer changes
5. ✅ **NEVER rebuild containers unless Gemfile/Dockerfile changed** - use `touch tmp/restart.txt` instead
6. ✅ Never start conflicting services or containers

