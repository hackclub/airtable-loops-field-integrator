# Strict rolling-window limiter using Redis ZSET
# Guarantees: no more than `limit` events in any `period` window.

class RateLimiter
  # redis: a Redis connection or pool
  # key:   unique bucket name, e.g. "rate:my_api"
  # limit: max events per window
  # period: window seconds (Float allowed)
  def initialize(redis:, key:, limit:, period:)
    @redis  = redis
    @key    = key
    @limit  = limit
    @period = period.to_f
  end

  # Blocks until a slot is available, then records one event.
  # Returns the Time used for the event.
  def acquire!
    loop do
      now_ms = (Process.clock_gettime(Process::CLOCK_REALTIME, :float_second) * 1000.0).to_i
      window_start_ms = now_ms - (@period * 1000).to_i

      # Lua keeps it atomic: trim old, count, add new if room
      period_ms = (@period * 1000).to_i
      script = <<~LUA
        local key     = KEYS[1]
        local now     = tonumber(ARGV[1])
        local winFrom = tonumber(ARGV[2])
        local limit   = tonumber(ARGV[3])
        local period  = tonumber(ARGV[4])

        -- remove old events
        redis.call("ZREMRANGEBYSCORE", key, 0, winFrom)
        local count = redis.call("ZCARD", key)

        if count < limit then
          redis.call("ZADD", key, now, tostring(now) .. "-" .. redis.call("INCR", key .. ":seq"))
          -- keep tidy: expire the bucket a bit beyond the sliding window period
          -- Use period + 2 second buffer to ensure old events aren't lost prematurely
          redis.call("PEXPIRE", key, math.floor(period + 2000))
          return 1
        else
          -- get the oldest event to know how long to wait
          local oldest = redis.call("ZRANGE", key, 0, 0, "WITHSCORES")
          return oldest[2] or 0
        end
      LUA

      res = @redis.eval(script, keys: [ @key ], argv: [ now_ms, window_start_ms, @limit, period_ms ])

      if res == 1
        return Time.at(now_ms / 1000.0)
      else
        # Need to wait until (oldest + period) is in the past
        oldest_ms = res.to_i
        sleep_ms  = (oldest_ms + (@period * 1000).to_i) - now_ms
        sleep_time = [ [ sleep_ms, 5 ].max, (@period * 1000).to_i ].min / 1000.0
        # tiny jitter to avoid thundering herd
        sleep(sleep_time + rand * 0.01)
      end
    end
  end
end
