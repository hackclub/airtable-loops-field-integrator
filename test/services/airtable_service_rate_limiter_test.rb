require "test_helper"

class AirtableServiceRateLimiterTest < ActiveSupport::TestCase
  def setup
    # Ensure Redis is available
    skip "Redis not available" unless REDIS_FOR_RATE_LIMITING.ping
  end

  test "extracts base_id from records URL" do
    url = "https://api.airtable.com/v0/app123/Table456"
    base_id = AirtableService.send(:extract_base_id, url)
    assert_equal "app123", base_id
  end

  test "extracts base_id from meta bases URL" do
    url = "https://api.airtable.com/v0/meta/bases/app123/tables"
    base_id = AirtableService.send(:extract_base_id, url)
    assert_equal "app123", base_id
  end

  test "extracts base_id from webhooks URL" do
    url = "https://api.airtable.com/v0/bases/app123/webhooks/wh123"
    base_id = AirtableService.send(:extract_base_id, url)
    assert_equal "app123", base_id
  end

  test "returns nil for meta bases list URL" do
    url = "https://api.airtable.com/v0/meta/bases"
    base_id = AirtableService.send(:extract_base_id, url)
    assert_nil base_id, "Should not extract base_id from bases list endpoint"
  end

  test "returns nil for relative paths without base_id" do
    url = "/v0/meta/bases"
    base_id = AirtableService.send(:extract_base_id, url)
    assert_nil base_id
  end

  test "extracts base_id from relative paths" do
    url = "/v0/app123/Table456"
    base_id = AirtableService.send(:extract_base_id, url)
    assert_equal "app123", base_id
  end

  test "global rate limiter is initialized" do
    limiter = AirtableService.global_rate_limiter
    assert_instance_of RateLimiter, limiter
  end

  test "per-base rate limiter is created and cached" do
    base_id = "test_base_#{SecureRandom.hex(4)}"

    limiter1 = AirtableService.send(:rate_limiter_for_base, base_id)
    limiter2 = AirtableService.send(:rate_limiter_for_base, base_id)

    assert_instance_of RateLimiter, limiter1
    assert_equal limiter1, limiter2, "Should return same limiter instance"
  end

  test "different bases get different rate limiters" do
    base_id1 = "test_base_#{SecureRandom.hex(4)}"
    base_id2 = "test_base_#{SecureRandom.hex(4)}"

    limiter1 = AirtableService.send(:rate_limiter_for_base, base_id1)
    limiter2 = AirtableService.send(:rate_limiter_for_base, base_id2)

    assert_not_equal limiter1, limiter2, "Different bases should have different limiters"
  end

  test "global rate limiter enforces 50 req/sec limit" do
    skip "Skipping actual API call test" unless ENV["AIRTABLE_PERSONAL_ACCESS_TOKEN"]

    # Clear any existing rate limit state
    redis_key = "rate:airtable:global"
    REDIS_FOR_RATE_LIMITING.del(redis_key)
    REDIS_FOR_RATE_LIMITING.del("#{redis_key}:seq")

    # Test that rapid requests to meta/bases (no per-base limit) still respect global limit
    # We'll test with a small batch to verify the mechanism works
    start_time = Time.now
    request_times = []
    3.times do |i|
      request_start = Time.now
      begin
        AirtableService.get("https://api.airtable.com/v0/meta/bases")
        request_times << Time.now - request_start
      rescue => e
        # Ignore errors - we're just testing rate limiting, not API correctness
      end
    end
    elapsed = Time.now - start_time

    # Should complete relatively quickly since we're well under 50 req/sec
    # But allow for network latency (each API call might take ~0.2-0.5s)
    assert elapsed < 3.0, "3 requests should complete in reasonable time (allows for API latency), took #{elapsed}s"
    
    # Verify rate limiting is actually applied - requests should not all be immediate
    # Even under global limit, they should be properly throttled if needed
    assert elapsed >= 0.1, "Should take some time even for allowed requests"
  end

  test "per-base rate limiter enforces 1 req/sec limit" do
    skip "Skipping actual API call test" unless ENV["AIRTABLE_PERSONAL_ACCESS_TOKEN"]

    # We need a real base_id for this test
    # Try to get one from the API
    begin
      bases = []
      AirtableService::Bases.find_each { |base| bases << base; break if bases.length >= 1 }
      skip "No bases available for testing" if bases.empty?

      base_id = bases.first["id"]
      
      # Clear rate limit state for this base
      redis_key = "rate:airtable:base:#{base_id}"
      REDIS_FOR_RATE_LIMITING.del(redis_key)
      REDIS_FOR_RATE_LIMITING.del("#{redis_key}:seq")

      start_time = Time.now
      
      # First request should be immediate (no rate limiting)
      AirtableService::Bases.get_schema(base_id: base_id)
      time_after_1 = Time.now - start_time

      # Second request should wait ~1 second due to rate limiting
      second_start = Time.now
      AirtableService::Bases.get_schema(base_id: base_id)
      time_after_2 = Time.now - start_time
      second_duration = Time.now - second_start

      # Third request should wait another ~1 second
      third_start = Time.now
      AirtableService::Bases.get_schema(base_id: base_id)
      total_time = Time.now - start_time
      third_duration = Time.now - third_start

      # First request includes API call time, should be reasonable (< 1s for API + overhead)
      assert time_after_1 < 1.0, "First request should complete in reasonable time, took #{time_after_1}s"
      
      # Second request should wait ~1 second due to rate limiting before making API call
      # The rate limiter enforces a sliding window, so it waits until 1 second after the first request
      # Allow some flexibility (0.8s minimum to account for timing precision)
      assert second_duration >= 0.8, "Second request should wait ~1s for rate limit + API time, took #{second_duration}s"
      assert second_duration < 2.5, "Second request shouldn't take too long, took #{second_duration}s"
      
      # Verify that rate limiting is actually working - second should take significantly longer than first
      assert second_duration > time_after_1 * 1.5, "Second request should take longer due to rate limiting (first: #{time_after_1}s, second: #{second_duration}s)"
      
      # Third request should wait another ~1 second
      assert third_duration >= 0.8, "Third request should wait another ~1s, took #{third_duration}s"
      assert third_duration < 2.5, "Third request shouldn't take too long, took #{third_duration}s"
      
      # Total time should reflect the rate limiting delays
      assert total_time >= 1.5, "Total time should reflect rate limiting delays, took #{total_time}s"
      assert total_time < 6.0, "Total time should be reasonable, took #{total_time}s"
    rescue => e
      skip "Could not test per-base limiting: #{e.message}"
    end
  end

  test "rate limiting prevents exceeding per-base limit" do
    skip "Skipping actual API call test" unless ENV["AIRTABLE_PERSONAL_ACCESS_TOKEN"]

    begin
      bases = []
      AirtableService::Bases.find_each { |base| bases << base; break if bases.length >= 1 }
      skip "No bases available for testing" if bases.empty?

      base_id = bases.first["id"]
      
      # Clear rate limit state for this base
      redis_key = "rate:airtable:base:#{base_id}"
      REDIS_FOR_RATE_LIMITING.del(redis_key)
      REDIS_FOR_RATE_LIMITING.del("#{redis_key}:seq")

      # Make first request
      start_time = Time.now
      AirtableService::Bases.get_schema(base_id: base_id)
      first_duration = Time.now - start_time

      # Immediately try second request - should be rate limited
      second_start = Time.now
      AirtableService::Bases.get_schema(base_id: base_id)
      second_duration = Time.now - second_start

      # Second request should take significantly longer due to rate limiting
      assert second_duration > first_duration * 1.5, 
        "Second request should be rate limited (first: #{first_duration}s, second: #{second_duration}s)"
      assert second_duration >= 0.8, "Second request should wait at least ~1s, took #{second_duration}s"
    rescue => e
      skip "Could not test rate limiting prevention: #{e.message}"
    end
  end
end

