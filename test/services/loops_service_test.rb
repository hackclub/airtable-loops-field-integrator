require "test_helper"
require "minitest/mock"

class LoopsServiceTest < ActiveSupport::TestCase
  def setup
    # Ensure Redis is available
    skip "Redis not available" unless REDIS_FOR_RATE_LIMITING.ping
    
    # Clear rate limit state before each test
    redis_key = "rate:loops:global"
    REDIS_FOR_RATE_LIMITING.del(redis_key)
    REDIS_FOR_RATE_LIMITING.del("#{redis_key}:seq")
    
    # Set test API key
    @original_api_key = ENV["LOOPS_API_KEY"]
    ENV["LOOPS_API_KEY"] = "test_api_key_123"
    
    # Reset HTTP client for each test
    LoopsService.instance_variable_set(:@http_client, nil)
    
    # Ensure the class is loaded and http_client method exists
    LoopsService.http_client rescue nil
  end

  def teardown
    # Restore original API key
    ENV["LOOPS_API_KEY"] = @original_api_key if @original_api_key
    
    # Clean up rate limit state
    redis_key = "rate:loops:global"
    REDIS_FOR_RATE_LIMITING.del(redis_key)
    REDIS_FOR_RATE_LIMITING.del("#{redis_key}:seq")
    
    # Reset HTTP client
    LoopsService.instance_variable_set(:@http_client, nil)
  end

  def create_mock_response(status:, body:, headers: {})
    mock_response = Minitest::Mock.new
    # Allow multiple calls to these methods - need at least 3-4 calls for error checking
    mock_response.expect :status, status
    mock_response.expect :status, status
    mock_response.expect :status, status
    mock_response.expect :body, body
    mock_response.expect :body, body
    mock_response.expect :body, body
    mock_response.expect :headers, headers
    mock_response.expect :headers, headers
    mock_response.expect :headers, headers
    mock_response.expect :error, nil
    mock_response.expect :error, nil
    mock_response.expect :error, nil
    mock_response.expect :error, nil
    mock_response.expect :json, JSON.parse(body)
    mock_response.expect :json, JSON.parse(body)
    mock_response.expect :json, JSON.parse(body)
    mock_response
  end

  def create_mock_response_with_error(error_message)
    mock_response = Minitest::Mock.new
    mock_error = Minitest::Mock.new
    mock_error.expect :message, error_message
    mock_response.expect :error, mock_error
    mock_response
  end

  test "normalize_email lowercases and trims whitespace" do
    assert_equal "test@example.com", LoopsService.send(:normalize_email, "Test@Example.com")
    assert_equal "test@example.com", LoopsService.send(:normalize_email, "  Test@Example.com  ")
    assert_equal "test@example.com", LoopsService.send(:normalize_email, "TEST@EXAMPLE.COM")
    assert_equal "test@example.com", LoopsService.send(:normalize_email, "  TEST@EXAMPLE.COM  ")
    assert_equal "", LoopsService.send(:normalize_email, "   ")
    assert_equal "", LoopsService.send(:normalize_email, "")
  end

  test "create_contact normalizes email" do
    mock_client = Minitest::Mock.new
    mock_response = create_mock_response(
      status: 201,
      body: '{"success":true,"id":"contact_123"}',
      headers: {}
    )
    
    # Verify email is normalized in the request
    mock_client.expect :post, mock_response do |url, **options|
      url.is_a?(String) && options[:json].is_a?(Hash) && options[:json][:email] == "test@example.com"
    end
    
    LoopsService.stub :http_client, mock_client do
      result = LoopsService.create_contact(email: "  Test@Example.com  ")
      assert_equal true, result["success"]
    end
    
    mock_client.verify
  end

  test "update_contact normalizes email" do
    mock_client = Minitest::Mock.new
    mock_response = create_mock_response(
      status: 200,
      body: '{"success":true,"id":"contact_789"}',
      headers: {}
    )
    
    # Verify email is normalized in the request
    mock_client.expect :put, mock_response do |url, **options|
      url.is_a?(String) && options[:json].is_a?(Hash) && options[:json][:email] == "test@example.com"
    end
    
    LoopsService.stub :http_client, mock_client do
      result = LoopsService.update_contact(email: "  Test@Example.com  ")
      assert_equal true, result["success"]
    end
    
    mock_client.verify
  end

  test "find_contact normalizes email" do
    mock_client = Minitest::Mock.new
    mock_response = create_mock_response(
      status: 200,
      body: '{"id":"contact_123","email":"test@example.com"}',
      headers: {}
    )
    
    # Verify email is normalized in the URL query string
    mock_client.expect :get, mock_response do |url|
      url.include?("email=test%40example.com")
    end
    
    LoopsService.stub :http_client, mock_client do
      result = LoopsService.find_contact(email: "  Test@Example.com  ")
      assert_equal "contact_123", result["id"]
    end
    
    mock_client.verify
  end

  test "global rate limiter is initialized" do
    limiter = LoopsService.global_rate_limiter
    assert_instance_of RateLimiter, limiter
  end

  test "rate limiting enforces 10 req/sec limit" do
    # This test verifies the rate limiter is configured correctly
    limiter = LoopsService.global_rate_limiter
    assert_equal 10, limiter.instance_variable_get(:@limit)
    assert_equal 1.0, limiter.instance_variable_get(:@period)
  end

  test "retries with exponential backoff on 429 response" do
    request_count = 0
    
    # Create mock HTTP client
    mock_client = Minitest::Mock.new
    
    # First request: 429 - needs to be HTTPX::HTTPError format
    mock_response_429 = Minitest::Mock.new
    # Create HTTPX::HTTPError for 429
    mock_error_response_429 = Minitest::Mock.new
    # Only status and headers are accessed in the successful retry path (lines 152, 175)
    mock_error_response_429.expect :status, 429  # Called once at line 152
    mock_error_response_429.expect :headers, { "x-ratelimit-limit" => "10", "x-ratelimit-remaining" => "0" }  # Called once at line 175
    
    mock_error_429 = Minitest::Mock.new
    # is_a? is called 3 times:
    # 1. Line 144: if response_error && !response_error.is_a?(HTTPX::HTTPError)
    # 2. Line 152: response_error.is_a?(HTTPX::HTTPError) 
    # 3. Line 175: response_error.is_a?(HTTPX::HTTPError)
    mock_error_429.expect :is_a?, true, [Class]  # Line 144 check
    mock_error_429.expect :is_a?, true, [Class]  # Line 152 check
    mock_error_429.expect :response, mock_error_response_429  # Called at line 152
    mock_error_429.expect :is_a?, true, [Class]  # Line 175 check
    mock_error_429.expect :response, mock_error_response_429  # Called at line 175
    
    # response.error is called once (now cached in service)
    mock_response_429.expect :error, mock_error_429
    
    # Second request: 200
    mock_response_200 = create_mock_response(
      status: 200,
      body: '[]',
      headers: {}
    )
    
    mock_client.expect :get, mock_response_429, [String]
    mock_client.expect :get, mock_response_200, [String]
    
    LoopsService.stub :http_client, mock_client do
      start_time = Time.now
      result = LoopsService.find_contact(email: "test@example.com")
      elapsed = Time.now - start_time

      # Should have waited at least 0.5s (initial backoff)
      assert elapsed >= 0.4, "Should have waited for exponential backoff, took #{elapsed}s"
      assert result.is_a?(Array)
    end
    
    # Verify all mocks were called correctly
    mock_client.verify
    mock_response_429.verify
    mock_error_429.verify
    mock_error_response_429.verify
  end

  test "raises RateLimitError after max retries exceeded" do
    # Create mock HTTP client that always returns 429
    mock_client = Minitest::Mock.new
    
    # Create 6 mock responses (initial + 5 retries)
    # For requests 1-5: status and headers are accessed (retry path)
    # For request 6: status, body, and json are accessed (max retries exceeded path)
    mock_responses = []
    mock_errors = []
    mock_error_responses = []
    
    6.times do |i|
      mock_response = Minitest::Mock.new
      
      # Create HTTPX::HTTPError for 429
      mock_error_response = Minitest::Mock.new
      
      # status is called once per request (line 152)
      mock_error_response.expect :status, 429
      
      # For requests 1-5: headers is called once (line 175)
      # For request 6: body and json are called once each (lines 160, 163)
      if i < 5
        # Requests 1-5: retry path - headers accessed
        mock_error_response.expect :headers, { "x-ratelimit-limit" => "10", "x-ratelimit-remaining" => "0" }
      else
        # Request 6: max retries exceeded - body and json accessed
        mock_error_response.expect :body, '{"success":false,"message":"Rate limit exceeded"}'
        mock_error_response.expect :json, { "success" => false, "message" => "Rate limit exceeded" }
      end
      
      mock_error = Minitest::Mock.new
      # is_a? is called 3 times per request:
      # 1. Line 144: if response_error && !response_error.is_a?(HTTPX::HTTPError)
      # 2. Line 152: response_error.is_a?(HTTPX::HTTPError) (for status check)
      # 3. Line 175 (requests 1-5) or Line 160 (request 6): response_error.is_a?(HTTPX::HTTPError)
      mock_error.expect :is_a?, true, [Class]  # Line 144 check
      mock_error.expect :is_a?, true, [Class]  # Line 152 check
      mock_error.expect :response, mock_error_response  # Called at line 152
      mock_error.expect :is_a?, true, [Class]  # Line 175 (requests 1-5) or Line 160 (request 6)
      mock_error.expect :response, mock_error_response  # Called at line 175 (requests 1-5) or Line 160 (request 6)
      
      # response.error is called once (now cached in service)
      mock_response.expect :error, mock_error
      
      mock_responses << mock_response
      mock_errors << mock_error
      mock_error_responses << mock_error_response
      mock_client.expect :get, mock_response, [String]
    end
    
    LoopsService.stub :http_client, mock_client do
      assert_raises(LoopsService::RateLimitError) do
        LoopsService.find_contact(email: "test@example.com")
      end
    end
    
    # Verify all mocks were called correctly
    mock_client.verify
    mock_responses.each(&:verify)
    mock_errors.each(&:verify)
    mock_error_responses.each(&:verify)
  end

  test "create_contact with valid email succeeds" do
    mock_client = Minitest::Mock.new
    mock_response = create_mock_response(
      status: 201,
      body: '{"success":true,"id":"contact_123"}',
      headers: {}
    )
    
    # HTTPX sends: post(url, json: body_hash) - use block for flexible matching
    mock_client.expect :post, mock_response do |url, **options|
      url.is_a?(String) && options[:json].is_a?(Hash)
    end
    
    LoopsService.stub :http_client, mock_client do
      result = LoopsService.create_contact(email: "test@example.com")
      assert_equal true, result["success"]
      assert_equal "contact_123", result["id"]
    end
    
    mock_client.verify
  end

  test "create_contact with all optional fields" do
    mock_client = Minitest::Mock.new
    mock_response = create_mock_response(
      status: 201,
      body: '{"success":true,"id":"contact_456"}',
      headers: {}
    )
    
    # HTTPX sends: post(url, json: body_hash)
    # Minitest::Mock needs flexible matching for keyword args
    mock_client.expect :post, mock_response do |url, **options|
      url.is_a?(String) && options[:json].is_a?(Hash)
    end
    
    LoopsService.stub :http_client, mock_client do
      result = LoopsService.create_contact(
        email: "test@example.com",
        firstName: "John",
        lastName: "Doe",
        source: "API",
        subscribed: true,
        userGroup: "premium",
        userId: "user_123",
        mailingLists: { "list_1" => true }
      )
      assert_equal true, result["success"]
      assert_equal "contact_456", result["id"]
    end
    
    mock_client.verify
  end

  test "create_contact returns error for existing contact" do
    mock_client = Minitest::Mock.new
    # Create an HTTPX::HTTPError mock for 409
    mock_error_response = Minitest::Mock.new
    mock_error_response.expect :status, 409
    mock_error_response.expect :status, 409
    mock_error_response.expect :body, '{"success":false,"message":"Contact already exists"}'
    mock_error_response.expect :body, '{"success":false,"message":"Contact already exists"}'
    mock_error_response.expect :headers, {}
    mock_error_response.expect :headers, {}
    mock_error_response.expect :json, { "success" => false, "message" => "Contact already exists" }
    mock_error_response.expect :json, { "success" => false, "message" => "Contact already exists" }
    
    mock_error = Minitest::Mock.new
    mock_error.expect :is_a?, true, [Class]  # HTTPX::HTTPError check
    mock_error.expect :response, mock_error_response
    mock_error.expect :is_a?, true, [Class]  # Second check
    mock_error.expect :response, mock_error_response
    mock_error.expect :is_a?, true, [Class]  # Third check
    mock_error.expect :response, mock_error_response
    
    mock_response = Minitest::Mock.new
    # response.error is called once (now cached in service)
    mock_response.expect :error, mock_error
    
    # HTTPX sends: post(url, json: body_hash)
    mock_client.expect :post, mock_response do |url, **options|
      url.is_a?(String) && options[:json].is_a?(Hash)
    end
    
    LoopsService.stub :http_client, mock_client do
      assert_raises(LoopsService::ApiError) do
        LoopsService.create_contact(email: "existing@example.com")
      end
    end
    
    mock_client.verify
  end

  test "update_contact with email succeeds" do
    mock_client = Minitest::Mock.new
    mock_response = create_mock_response(
      status: 200,
      body: '{"success":true,"id":"contact_789"}',
      headers: {}
    )
    
    # HTTPX sends: put(url, json: body_hash)
    mock_client.expect :put, mock_response do |url, **options|
      url.is_a?(String) && options[:json].is_a?(Hash)
    end
    
    LoopsService.stub :http_client, mock_client do
      result = LoopsService.update_contact(email: "test@example.com", firstName: "Jane")
      assert_equal true, result["success"]
      assert_equal "contact_789", result["id"]
    end
    
    mock_client.verify
  end

  test "update_contact with userId succeeds" do
    mock_client = Minitest::Mock.new
    mock_response = create_mock_response(
      status: 200,
      body: '{"success":true,"id":"contact_999"}',
      headers: {}
    )
    
    # HTTPX sends: put(url, json: body_hash)
    mock_client.expect :put, mock_response do |url, **options|
      url.is_a?(String) && options[:json].is_a?(Hash)
    end
    
    LoopsService.stub :http_client, mock_client do
      result = LoopsService.update_contact(userId: "user_456")
      assert_equal true, result["success"]
      assert_equal "contact_999", result["id"]
    end
    
    mock_client.verify
  end

  test "update_contact creates new contact if not found" do
    mock_client = Minitest::Mock.new
    mock_response = create_mock_response(
      status: 200,
      body: '{"success":true,"id":"contact_new"}',
      headers: {}
    )
    
    # HTTPX sends: put(url, json: body_hash)
    mock_client.expect :put, mock_response do |url, **options|
      url.is_a?(String) && options[:json].is_a?(Hash)
    end
    
    LoopsService.stub :http_client, mock_client do
      result = LoopsService.update_contact(email: "new@example.com")
      assert_equal true, result["success"]
    end
    
    mock_client.verify
  end

  test "find_contact by email succeeds" do
    mock_client = Minitest::Mock.new
    mock_response = create_mock_response(
      status: 200,
      body: '[{"id":"contact_123","email":"test@example.com","firstName":"John"}]',
      headers: {}
    )
    
    mock_client.expect :get, mock_response, [String]
    
    LoopsService.stub :http_client, mock_client do
      result = LoopsService.find_contact(email: "test@example.com")
      assert_equal 1, result.length
      assert_equal "contact_123", result.first["id"]
      assert_equal "test@example.com", result.first["email"]
    end
    
    mock_client.verify
  end

  test "find_contact by userId succeeds" do
    mock_client = Minitest::Mock.new
    mock_response = create_mock_response(
      status: 200,
      body: '[{"id":"contact_456","userId":"user_123"}]',
      headers: {}
    )
    
    mock_client.expect :get, mock_response, [String]
    
    LoopsService.stub :http_client, mock_client do
      result = LoopsService.find_contact(userId: "user_123")
      assert_equal 1, result.length
      assert_equal "contact_456", result.first["id"]
    end
    
    mock_client.verify
  end

  test "find_contact returns empty array when not found" do
    mock_client = Minitest::Mock.new
    mock_response = create_mock_response(
      status: 200,
      body: "[]",
      headers: {}
    )
    
    mock_client.expect :get, mock_response, [String]
    
    LoopsService.stub :http_client, mock_client do
      result = LoopsService.find_contact(email: "notfound@example.com")
      assert_equal [], result
    end
    
    mock_client.verify
  end

  test "find_contact raises error if both email and userId provided" do
    assert_raises(ArgumentError) do
      LoopsService.find_contact(email: "test@example.com", userId: "user_123")
    end
  end

  test "find_contact raises error if neither email nor userId provided" do
    assert_raises(ArgumentError) do
      LoopsService.find_contact
    end
  end

  test "create_property succeeds" do
    mock_client = Minitest::Mock.new
    mock_response = create_mock_response(
      status: 200,
      body: '{"success":true}',
      headers: {}
    )
    
    # HTTPX sends: post(url, json: body_hash)
    mock_client.expect :post, mock_response do |url, **options|
      url.is_a?(String) && options[:json].is_a?(Hash)
    end
    
    LoopsService.stub :http_client, mock_client do
      result = LoopsService.create_property(name: "favoriteColor", type: "string")
      assert_equal true, result["success"]
    end
    
    mock_client.verify
  end

  test "list_properties returns all properties" do
    mock_client = Minitest::Mock.new
    mock_response = create_mock_response(
      status: 200,
      body: '[{"key":"firstName","label":"First Name","type":"string"},{"key":"email","label":"Email","type":"string"}]',
      headers: {}
    )
    
    mock_client.expect :get, mock_response, [String]
    
    LoopsService.stub :http_client, mock_client do
      result = LoopsService.list_properties
      assert_equal 2, result.length
      assert_equal "firstName", result.first["key"]
    end
    
    mock_client.verify
  end

  test "list_properties with custom filter" do
    mock_client = Minitest::Mock.new
    mock_response = create_mock_response(
      status: 200,
      body: '[{"key":"customProp","label":"Custom Prop","type":"string"}]',
      headers: {}
    )
    
    mock_client.expect :get, mock_response, [String]
    
    LoopsService.stub :http_client, mock_client do
      result = LoopsService.list_properties(list: "custom")
      assert_equal 1, result.length
      assert_equal "customProp", result.first["key"]
    end
    
    mock_client.verify
  end

  test "list_mailing_lists succeeds" do
    mock_client = Minitest::Mock.new
    mock_response = create_mock_response(
      status: 200,
      body: '[{"id":"list_1","name":"Beta Users","description":"Beta testers","isPublic":true},{"id":"list_2","name":"Newsletter","description":null,"isPublic":false}]',
      headers: {}
    )
    
    mock_client.expect :get, mock_response, [String]
    
    LoopsService.stub :http_client, mock_client do
      result = LoopsService.list_mailing_lists
      assert_equal 2, result.length
      assert_equal "list_1", result.first["id"]
      assert_equal "Beta Users", result.first["name"]
      assert_equal true, result.first["isPublic"]
    end
    
    mock_client.verify
  end

  test "list_mailing_lists returns empty array when no lists" do
    mock_client = Minitest::Mock.new
    mock_response = create_mock_response(
      status: 200,
      body: "[]",
      headers: {}
    )
    
    mock_client.expect :get, mock_response, [String]
    
    LoopsService.stub :http_client, mock_client do
      result = LoopsService.list_mailing_lists
      assert_equal [], result
    end
    
    mock_client.verify
  end
end
