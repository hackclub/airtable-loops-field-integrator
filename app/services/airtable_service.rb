class AirtableService
  API_URL = "https://api.airtable.com/v0"
  META_API_URL = "#{API_URL}/meta"

  def self.api_token
    ENV.fetch("AIRTABLE_PERSONAL_ACCESS_TOKEN")
  end

  # Get the global rate limiter (lazy initialization)
  # Global: 50 requests per second across all bases
  def self.global_rate_limiter
    @global_rate_limiter ||= RateLimiter.new(
      redis: REDIS_FOR_RATE_LIMITING,
      key: "rate:airtable:global",
      limit: 50,
      period: 1.0
    )
  end

  class RateLimitError < StandardError
    def initialize(response_body)
      error_info = JSON.parse(response_body) rescue nil
      message = error_info&.dig("errors", 0, "message") || "Rate limit exceeded"
      super(message)
    end
  end

  class TimeoutError < StandardError
    def initialize(url, message)
      super("Airtable API request timed out after 60 seconds: #{url}, #{message}")
    end
  end

  class << self
    def get(url)
      make_request(:get, url)
    end

    def post(url, body)
      make_request(:post, url, body: body)
    end

    def patch(url, body)
      make_request(:patch, url, body: body)
    end

    def delete(url)
      make_request(:delete, url)
    end

    private

    # Extract base_id from Airtable API URL
    # Supports patterns like:
    # - /v0/{base_id}/{table_id}
    # - /v0/meta/bases/{base_id}/tables
    # - /v0/bases/{base_id}/webhooks/...
    def extract_base_id(url)
      # Remove the API URL prefix if present
      path = url.sub(%r{^https?://[^/]+}, "")
      
      # Pattern 1: /v0/meta/bases/{base_id}/... (check this first to avoid matching "meta" as base_id)
      match = path.match(%r{^/v0/meta/bases/([^/]+)})
      return match[1] if match
      
      # Pattern 2: /v0/bases/{base_id}/... (check before generic pattern)
      match = path.match(%r{^/v0/bases/([^/]+)})
      return match[1] if match
      
      # Pattern 3: /v0/{base_id}/{table_id} (records endpoint - must not be "meta" or "bases")
      match = path.match(%r{^/v0/([^/]+)/[^/]+(?:\?|$)})
      if match && match[1] != "meta" && match[1] != "bases"
        return match[1]
      end
      
      nil
    end

    # Get or create a per-base rate limiter
    # Limit: 1 request per second per base
    def rate_limiter_for_base(base_id)
      @base_limiters ||= {}
      @base_limiters[base_id] ||= RateLimiter.new(
        redis: REDIS_FOR_RATE_LIMITING,
        key: "rate:airtable:base:#{base_id}",
        limit: 1,
        period: 1.0
      )
    end

    def make_request(method, url, body: nil)
      # Apply global rate limiting first (50 req/sec)
      global_rate_limiter.acquire!

      # Apply per-base rate limiting if base_id can be extracted (1 req/sec per base)
      base_id = extract_base_id(url)
      if base_id
        rate_limiter_for_base(base_id).acquire!
      end
      client = HTTPX.with(
        headers: {
          "Authorization" => "Bearer #{api_token}",
          "Content-Type" => "application/json"
        }
      )

      response = if body
        client.send(method, url, json: body)
      else
        client.send(method, url)
      end

      if response.error
        if response.error.message.include?("Timed out")
          raise TimeoutError.new(url, response.error.message)
        end

        if response.error.message.include?("Rate limit")
          raise RateLimitError.new(response.error.message)
        end

        raise "Airtable API error: #{response.error.message}"
      end

      # PATCH requests can return 200 (OK) for successful updates
      unless [200, 201].include?(response.status)
        error_body = response.body.to_s
        # Try to parse JSON error if available
        begin
          error_json = response.json rescue nil
          error_msg = error_json ? error_json.inspect : error_body
        rescue
          error_msg = error_body
        end
        raise "Airtable API error: #{response.status} - #{error_msg}"
      end

      return nil if response.body.to_s.empty?
      response.json
    end
  end

  class Bases
    def self.find_each(&block)
      return enum_for(:find_each) unless block_given?

      offset = nil
      loop do
        response = fetch_bases(offset)
        bases = response["bases"]
        
        bases.each(&block)
        
        offset = response["offset"]
        break unless offset
      end
    end

    def self.get_schema(base_id:, include_visible_field_ids: false)
      url = "#{META_API_URL}/bases/#{base_id}/tables"
      url += "?include[]=visibleFieldIds" if include_visible_field_ids
      
      response = AirtableService.get(url)
      
      # Index tables by ID for easier lookup
      tables_by_id = {}
      response["tables"].each do |table|
        tables_by_id[table["id"]] = table
      end
      
      tables_by_id
    end

    def self.update_table_schema(base_id:, table_id:, fields:)
      # Use Metadata API endpoint to update table schema
      # According to Airtable API docs, fields can be added via PATCH to /v0/meta/bases/{baseId}/tables/{tableId}
      # or POST to /v0/meta/bases/{baseId}/tables/{tableId}/fields
      # Try PATCH first as it's the standard approach for updates
      url = "#{META_API_URL}/bases/#{base_id}/tables/#{table_id}"
      # Ensure body is properly formatted with string keys
      body = { "fields" => fields }
      AirtableService.patch(url, body)
    end

    def self.add_field(base_id:, table_id:, field:)
      # Alternative: POST to /fields endpoint to add a single field
      url = "#{META_API_URL}/bases/#{base_id}/tables/#{table_id}/fields"
      AirtableService.post(url, field)
    end

    private

    def self.fetch_bases(offset = nil)
      url = "#{META_API_URL}/bases"
      url += "?offset=#{offset}" if offset
      AirtableService.get(url)
    end
  end

  class Records
    def self.list(base_id:, table_id:, offset: nil, max_records: nil, filter_formula: nil)
      url = "#{API_URL}/#{base_id}/#{table_id}"
      params = []
      params << "offset=#{offset}" if offset
      params << "maxRecords=#{max_records}" if max_records
      if filter_formula
        # URL encode the filter formula
        params << "filterByFormula=#{CGI.escape(filter_formula)}"
      end
      url += "?#{params.join('&')}" if params.any?
      
      AirtableService.get(url)
    end

    def self.find_each(base_id:, table_id:, &block)
      return enum_for(:find_each, base_id: base_id, table_id: table_id) unless block_given?

      offset = nil
      loop do
        response = list(base_id: base_id, table_id: table_id, offset: offset)
        records = response["records"]
        
        records.each(&block)
        
        offset = response["offset"]
        break unless offset
      end
    end
  end

  class Webhooks
    def self.create(base_id:, notification_url: nil, specification:)
      url = "#{API_URL}/bases/#{base_id}/webhooks"
      
      body = {
        specification: specification
      }
      body[:notificationUrl] = notification_url if notification_url

      AirtableService.post(url, body)
    end

    def self.delete(base_id:, webhook_id:)
      url = "#{API_URL}/bases/#{base_id}/webhooks/#{webhook_id}"
      AirtableService.delete(url)
    end

    def self.refresh(base_id:, webhook_id:)
      url = "#{API_URL}/bases/#{base_id}/webhooks/#{webhook_id}/refresh"
      AirtableService.post(url, nil)
    end

    def self.payloads(base_id:, webhook_id:, start_cursor: nil)
      url = "#{API_URL}/bases/#{base_id}/webhooks/#{webhook_id}/payloads"
      url += "?cursor=#{start_cursor}" if start_cursor
      
      AirtableService.get(url)
    end
  end
end

