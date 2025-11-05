require "test_helper"

class LlmCacheTest < ActiveSupport::TestCase
  def setup
    LlmCache.destroy_all
  end

  def teardown
    LlmCache.destroy_all
  end

  test "calculates bytes size correctly" do
    cache = LlmCache.create!(
      prompt_hash: "abc123",
      request_json: { "test" => "data" },
      response_json: { "parsed" => { "result" => "value" } },
      bytes_size: 0
    )

    # The bytes_size should be updated after save
    assert cache.bytes_size > 0
  end

  test "touches last_used_at" do
    cache = LlmCache.create!(
      prompt_hash: "abc123",
      request_json: {},
      response_json: { "parsed" => {} },
      bytes_size: 100,
      last_used_at: 1.day.ago
    )

    old_time = cache.last_used_at
    sleep 1 # Ensure time difference
    cache.touch_last_used!

    assert cache.reload.last_used_at > old_time
  end

  test "finds by prompt_hash" do
    cache = LlmCache.create!(
      prompt_hash: "test_hash_123",
      request_json: {},
      response_json: { "parsed" => { "result" => "cached" } },
      bytes_size: 100
    )

    found = LlmCache.find_by(prompt_hash: "test_hash_123")
    assert_not_nil found
    assert_equal "cached", found.response_json["parsed"]["result"]
  end
end
