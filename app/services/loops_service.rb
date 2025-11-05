require_relative "../lib/email_normalizer"

class LoopsService
  API_URL = "https://app.loops.so/api/v1"

  def self.api_token
    ENV.fetch("LOOPS_API_KEY")
  end

  # Get the global rate limiter (lazy initialization)
  # Global: 10 requests per second
  def self.global_rate_limiter
    @global_rate_limiter ||= RateLimiter.new(
      redis: REDIS_FOR_RATE_LIMITING,
      key: "rate:loops:global",
      limit: 10,
      period: 1.0
    )
  end

  # Get the configured rate limit (requests per second)
  def self.rate_limit_rps
    global_rate_limiter.instance_variable_get(:@limit)
  end

  class RateLimitError < StandardError
    def initialize(message = "Rate limit exceeded")
      super(message)
    end
  end

  class TimeoutError < StandardError
    def initialize(url, message)
      super("Loops API request timed out: #{url}, #{message}")
    end
  end

  class ApiError < StandardError
    attr_reader :status_code, :response_body

    def initialize(status_code, response_body)
      @status_code = status_code
      @response_body = response_body

      # Try to parse error message from JSON response
      error_message = begin
        error_json = JSON.parse(response_body) rescue nil
        error_json&.dig("message") || "Loops API error: #{status_code}"
      rescue
        "Loops API error: #{status_code}"
      end

      super(error_message)
    end
  end

  class << self
    # Create a new contact
    def create_contact(email:, **kwargs)
      email = EmailNormalizer.normalize(email)
      body = { email: email }.merge(kwargs)
      make_request(:post, "#{API_URL}/contacts/create", body: body)
    end

    # Update or create a contact
    def update_contact(email: nil, userId: nil, **kwargs)
      unless email || userId
        raise ArgumentError, "Either email or userId must be provided"
      end

      body = {}
      body[:email] = EmailNormalizer.normalize(email) if email
      body[:userId] = userId if userId
      body.merge!(kwargs)

      make_request(:put, "#{API_URL}/contacts/update", body: body)
    end

    # Find a contact by email or userId
    def find_contact(email: nil, userId: nil)
      if email && userId
        raise ArgumentError, "Only one of email or userId can be provided"
      end
      unless email || userId
        raise ArgumentError, "Either email or userId must be provided"
      end

      params = {}
      params[:email] = EmailNormalizer.normalize(email) if email
      params[:userId] = userId if userId

      query_string = params.map { |k, v| "#{k}=#{CGI.escape(v.to_s)}" }.join("&")
      url = "#{API_URL}/contacts/find?#{query_string}"

      make_request(:get, url)
    end

    # Create a contact property
    def create_property(name:, type:)
      body = { name: name, type: type }
      make_request(:post, "#{API_URL}/contacts/properties", body: body)
    end

    # List contact properties
    def list_properties(list: nil)
      url = "#{API_URL}/contacts/properties"
      url += "?list=#{CGI.escape(list)}" if list
      make_request(:get, url)
    end

    # List mailing lists
    def list_mailing_lists
      make_request(:get, "#{API_URL}/lists")
    end

    private

    # Public for testing purposes
    def http_client
      @http_client ||= HTTPX.with(
        headers: {
          "Authorization" => "Bearer #{api_token}",
          "Content-Type" => "application/json"
        }
      )
    end

    def make_request(method, url, body: nil, max_retries: 5, retry_count: 0)
      # Apply global rate limiting (10 req/sec)
      global_rate_limiter.acquire!

      initial_backoff = 0.5

      begin
        client = http_client

        response = if body
          client.send(method, url, json: body)
        else
          client.send(method, url)
        end

        # Check for HTTP errors (but 404/400/etc are still valid responses with status codes)
        # Store error check result to avoid multiple calls
        response_error = response.error
        if response_error && !response_error.is_a?(HTTPX::HTTPError)
          if response_error.message.include?("Timed out")
            raise TimeoutError.new(url, response_error.message)
          end
          raise "Loops API error: #{response_error.message}"
        end

        # Get status code - HTTPX::HTTPError responses still have status codes
        status = response_error.is_a?(HTTPX::HTTPError) ? response_error.response.status : response.status

        # Handle 429 Rate Limit responses with retry
        if status == 429
          new_retry_count = retry_count + 1

          if new_retry_count > max_retries
            # Get error body and message
            resp_obj = response_error.is_a?(HTTPX::HTTPError) ? response_error.response : response
            error_body = resp_obj.body.to_s
            begin
              error_json = resp_obj.json rescue nil
              error_msg = error_json&.dig("message") || "Rate limit exceeded"
            rescue
              error_msg = "Rate limit exceeded after #{max_retries} retries"
            end
            raise RateLimitError.new(error_msg)
          end

          # Calculate exponential backoff delay
          backoff_delay = initial_backoff * (2 ** (new_retry_count - 1))

          # Optionally use rate limit headers to determine wait time
          resp_obj = response_error.is_a?(HTTPX::HTTPError) ? response_error.response : response
          headers = resp_obj.headers
          # HTTPX headers can be accessed as hash with string or symbol keys, case-insensitive
          rate_limit_remaining = headers["x-ratelimit-remaining"] ||
                                  headers[:"x-ratelimit-remaining"] ||
                                  headers["X-RateLimit-Remaining"] ||
                                  headers[:"X-RateLimit-Remaining"]
          rate_limit_remaining = rate_limit_remaining.to_i if rate_limit_remaining
          if rate_limit_remaining && rate_limit_remaining == 0
            # If rate limit is exhausted, wait longer
            # Calculate wait time based on rate limit window (1 second)
            backoff_delay = [ backoff_delay, 1.0 ].max
          end

          sleep(backoff_delay)

          # Retry the request
          return make_request(method, url, body: body, max_retries: max_retries, retry_count: new_retry_count)
        end

        # Handle other error status codes
        unless [ 200, 201 ].include?(status)
          resp_obj = response_error.is_a?(HTTPX::HTTPError) ? response_error.response : response
          error_body = resp_obj.body.to_s
          begin
            error_json = resp_obj.json rescue nil
            error_msg = error_json ? error_json.inspect : error_body
          rescue
            error_msg = error_body
          end
          raise ApiError.new(status, error_body)
        end

        # Parse JSON response
        resp_obj = response_error.is_a?(HTTPX::HTTPError) ? response_error.response : response
        return nil if resp_obj.body.to_s.empty?

        begin
          resp_obj.json
        rescue => e
          # If JSON parsing fails, return raw body or empty hash
          resp_obj.body.to_s.empty? ? {} : { "body" => resp_obj.body.to_s }
        end
      rescue RateLimitError, TimeoutError, ApiError
        # Re-raise custom errors
        raise
      rescue => e
        # Wrap unexpected errors
        raise "Loops API error: #{e.message}"
      end
    end
  end
end
