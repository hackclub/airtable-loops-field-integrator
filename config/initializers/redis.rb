# Redis connection for rate limiting
# Uses a separate connection from Sidekiq to avoid conflicts

REDIS_FOR_RATE_LIMITING = Redis.new(url: ENV.fetch("REDIS_URL", "redis://redis:6379/0"))
