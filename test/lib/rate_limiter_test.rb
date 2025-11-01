require "test_helper"

class RateLimiterTest < ActiveSupport::TestCase
  def setup
    @redis = REDIS_FOR_RATE_LIMITING
    # Use unique keys for each test to avoid interference
    @test_key_prefix = "rate:test:#{SecureRandom.hex(8)}"
  end

  def teardown
    # Clean up test keys
    @redis.del("#{@test_key_prefix}:*") if @test_key_prefix
  end

  test "allows requests up to the limit" do
    limiter = RateLimiter.new(
      redis: @redis,
      key: "#{@test_key_prefix}:allow",
      limit: 5,
      period: 1.0
    )

    # Should allow 5 requests immediately
    times = []
    5.times do
      time = limiter.acquire!
      times << time
    end

    assert_equal 5, times.length
    # All should be acquired within a short time window (first 5 should be quick)
    elapsed = times.last - times.first
    assert elapsed < 0.1, "First 5 requests should be immediate, took #{elapsed}s"
  end

  test "enforces rate limit and blocks when limit exceeded" do
    limiter = RateLimiter.new(
      redis: @redis,
      key: "#{@test_key_prefix}:enforce",
      limit: 2,
      period: 1.0
    )

    start_time = Time.now

    # First 2 should be immediate
    2.times { limiter.acquire! }
    time_after_2 = Time.now - start_time

    # 3rd request should be blocked for ~1 second
    limiter.acquire!
    time_after_3 = Time.now - start_time

    # Verify timing: first 2 should be fast, 3rd should wait
    assert time_after_2 < 0.2, "First 2 requests should be immediate"
    assert time_after_3 >= 0.9, "3rd request should wait ~1 second, waited #{time_after_3}s"
    assert time_after_3 < 2.0, "3rd request shouldn't wait too long, waited #{time_after_3}s"
  end

  test "respects sliding window period" do
    limiter = RateLimiter.new(
      redis: @redis,
      key: "#{@test_key_prefix}:window",
      limit: 3,
      period: 2.0
    )

    start_time = Time.now

    # Request 3 immediately
    3.times { limiter.acquire! }
    time_after_3 = Time.now - start_time

    # 4th request should be blocked
    limiter.acquire!
    time_after_4 = Time.now - start_time

    assert time_after_3 < 0.2, "First 3 requests should be immediate"
    # Should wait approximately the period (2 seconds)
    assert time_after_4 >= 1.8, "Should wait ~2 seconds for window, waited #{time_after_4}s"
    assert time_after_4 < 3.0, "Shouldn't wait too long, waited #{time_after_4}s"
  end

  test "allows bursts after window expires" do
    limiter = RateLimiter.new(
      redis: @redis,
      key: "#{@test_key_prefix}:burst",
      limit: 2,
      period: 0.5
    )

    start_time = Time.now

    # Use up the limit
    2.times { limiter.acquire! }

    # Wait for window to expire
    sleep(0.6)

    # Should allow another burst
    burst_start = Time.now
    2.times { limiter.acquire! }
    burst_duration = Time.now - burst_start

    # New burst should be immediate
    assert burst_duration < 0.2, "New burst after window should be immediate, took #{burst_duration}s"
  end

  test "different limiters have independent limits" do
    limiter1 = RateLimiter.new(
      redis: @redis,
      key: "#{@test_key_prefix}:indep1",
      limit: 2,
      period: 1.0
    )

    limiter2 = RateLimiter.new(
      redis: @redis,
      key: "#{@test_key_prefix}:indep2",
      limit: 2,
      period: 1.0
    )

    # Use up limiter1's limit
    2.times { limiter1.acquire! }

    # Limiter2 should still allow requests
    start_time = Time.now
    2.times { limiter2.acquire! }
    duration = Time.now - start_time

    assert duration < 0.2, "Limiter2 should be independent and allow immediate requests, took #{duration}s"
  end

  test "handles concurrent requests correctly" do
    limiter = RateLimiter.new(
      redis: @redis,
      key: "#{@test_key_prefix}:concurrent",
      limit: 5,
      period: 1.0
    )

    start_time = Time.now
    threads = []

    # Simulate 10 concurrent requests
    10.times do |i|
      threads << Thread.new do
        limiter.acquire!
      end
    end

    threads.each(&:join)
    total_time = Time.now - start_time

    # Should take approximately 1 second (first 5 immediate, next 5 wait ~1 second)
    assert total_time >= 0.9, "Concurrent requests should respect limit, took #{total_time}s"
    assert total_time < 2.0, "Shouldn't take too long, took #{total_time}s"
  end

  test "raises error when Redis connection fails" do
    # Create a mock Redis that will fail
    bad_redis = Object.new
    def bad_redis.eval(*args)
      raise Redis::ConnectionError, "Connection failed"
    end

    limiter = RateLimiter.new(
      redis: bad_redis,
      key: "#{@test_key_prefix}:error",
      limit: 5,
      period: 1.0
    )

    # Should raise an error when trying to acquire
    assert_raises(Redis::ConnectionError) do
      limiter.acquire!
    end
  end

  test "handles very low limits correctly" do
    limiter = RateLimiter.new(
      redis: @redis,
      key: "#{@test_key_prefix}:lowlimit",
      limit: 1,
      period: 0.5
    )

    start_time = Time.now

    # First request should be immediate
    limiter.acquire!
    time_after_1 = Time.now - start_time

    # Second request should wait ~0.5 seconds
    limiter.acquire!
    time_after_2 = Time.now - start_time

    assert time_after_1 < 0.1, "First request should be immediate"
    assert time_after_2 >= 0.4, "Second request should wait ~0.5s, took #{time_after_2}s"
    assert time_after_2 < 1.0, "Shouldn't wait too long, took #{time_after_2}s"
  end

  test "different periods work correctly" do
    short_limiter = RateLimiter.new(
      redis: @redis,
      key: "#{@test_key_prefix}:short",
      limit: 2,
      period: 0.3
    )

    long_limiter = RateLimiter.new(
      redis: @redis,
      key: "#{@test_key_prefix}:long",
      limit: 2,
      period: 1.5
    )

    # Use up both limits
    short_limiter.acquire!
    short_limiter.acquire!
    long_limiter.acquire!
    long_limiter.acquire!

    start_time = Time.now

    # Short period should allow next request sooner
    short_limiter.acquire!
    short_duration = Time.now - start_time

    start_time = Time.now
    long_limiter.acquire!
    long_duration = Time.now - start_time

    # Short period limiter should release sooner (after ~0.3s)
    assert short_duration >= 0.2, "Short period limiter should allow request sooner"
    assert short_duration < 0.6, "Shouldn't wait too long"

    # Long period limiter should wait longer (after ~1.5s)
    # Allow some margin for timing precision
    assert long_duration >= 1.1, "Long period limiter should wait longer, took #{long_duration}s"
    assert long_duration < 2.0, "Shouldn't wait too long"
  end

  test "prevents exceeding limit by blocking until window clears" do
    limiter = RateLimiter.new(
      redis: @redis,
      key: "#{@test_key_prefix}:prevent",
      limit: 3,
      period: 1.0
    )

    start_time = Time.now

    # Make 3 requests (at the limit)
    3.times { limiter.acquire! }
    time_at_limit = Time.now - start_time

    # 4th request should be blocked
    limiter.acquire!
    time_after_block = Time.now - start_time

    # Verify the 4th request was actually blocked
    # Should take significantly longer than just making 3 requests
    block_duration = time_after_block - time_at_limit

    assert time_at_limit < 0.2, "First 3 requests should be immediate"
    assert block_duration >= 0.8, "4th request should be blocked for ~1 second, was blocked for #{block_duration}s"
    assert block_duration < 1.5, "Shouldn't be blocked too long, was blocked for #{block_duration}s"
  end

  test "rate limiter keys are isolated per instance" do
    limiter_a = RateLimiter.new(
      redis: @redis,
      key: "#{@test_key_prefix}:isolated_a",
      limit: 1,
      period: 1.0
    )

    limiter_b = RateLimiter.new(
      redis: @redis,
      key: "#{@test_key_prefix}:isolated_b",
      limit: 1,
      period: 1.0
    )

    # Use up limiter_a's limit
    limiter_a.acquire!

    # Limiter_b should still allow a request immediately (different key)
    start_time = Time.now
    limiter_b.acquire!
    duration = Time.now - start_time

    assert duration < 0.2, "Different keys should have independent limits, took #{duration}s"
  end

  test "expiration time is based on period, not limit" do
    # Test with limit=1, period=60 to verify expiration uses period
    test_key = "#{@test_key_prefix}:expire_test"
    limiter = RateLimiter.new(
      redis: @redis,
      key: test_key,
      limit: 1,
      period: 60.0
    )

    limiter.acquire!

    # Check TTL - should be approximately 60 seconds (period) + 2 seconds (buffer) = 62 seconds
    ttl = @redis.ttl(test_key)
    
    # TTL should be close to 62 seconds (60s period + 2s buffer)
    # Allow some margin for timing precision
    assert ttl >= 55, "TTL should be based on period (60s), not limit. Got #{ttl}s, expected ~62s"
    assert ttl <= 65, "TTL shouldn't be too long. Got #{ttl}s, expected ~62s"
  end
end

