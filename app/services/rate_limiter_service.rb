# Note: This only works if there is a single process running the code.
# If there are multiple processes, the rate limit will be exceeded.
module RateLimiterService
  class TokenBucket
    def initialize(rate, max_tokens)
      @mutex = Mutex.new
      @rate = rate
      @max_tokens = max_tokens
      @tokens = max_tokens
      @last_updated = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def wait_turn
      @mutex.synchronize do
        loop do
          now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          time_passed = now - @last_updated
          new_tokens = (time_passed * @rate).floor
          
          if new_tokens > 0
            @tokens = [@tokens + new_tokens, @max_tokens].min
            @last_updated = now
          end
          
          if @tokens >= 1
            @tokens -= 1
            break
          end
          
          # Calculate sleep time to get next token
          sleep_time = (1.0 / @rate) - (time_passed % (1.0 / @rate))
          sleep(sleep_time)
        end
      end
    end
  end

  class AirtableRateLimiter
    @buckets = Concurrent::Map.new

    class << self
      def [](base_id)
        @buckets.compute_if_absent(base_id) do
          TokenBucket.new(2.0, 2) # 2 requests per second per base
        end
      end
    end
  end

  class Loops
    @bucket = TokenBucket.new(3.0, 3) # 3 requests per second

    class << self
      def wait_turn
        @bucket.wait_turn
      end
    end
  end

  def self.Airtable(base_id)
    AirtableRateLimiter[base_id]
  end
end
