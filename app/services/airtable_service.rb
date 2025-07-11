class AirtableService
  API_TOKEN = Rails.application.credentials.airtable_personal_access_token
  API_URL = "https://api.airtable.com/v0"
  META_API_URL = "#{API_URL}/meta"

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

    def delete(url)
      make_request(:delete, url)
    end

    private

    def make_request(method, url, body: nil)
      client = HTTPX.with(
        headers: {
          "Authorization" => "Bearer #{API_TOKEN}",
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

      unless response.status == 200
        raise "Airtable API error: #{response.status} - #{response.body.to_s}"
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
      RateLimiterService::Airtable(base_id).wait_turn
      
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

    def self.get_cached_schema(base_id:, include_visible_field_ids: false, expires_in: 5.minutes)
      cache_key = "airtable/schema/#{base_id}/#{include_visible_field_ids}"
      
      Rails.cache.fetch(cache_key, expires_in: expires_in) do
        get_schema(
          base_id: base_id,
          include_visible_field_ids: include_visible_field_ids
        )
      end
    end

    def self.find_cached(base_id)
      Rails.cache.fetch("airtable/bases", expires_in: 1.hour) do
        # Collect all bases into an array
        bases = []
        find_each { |base| bases << base }
        bases
      end.find { |base| base["id"] == base_id }
    end

    def self.clear_schema_cache(base_id, include_visible_field_ids: false)
      Rails.cache.delete("airtable/schema/#{base_id}/#{include_visible_field_ids}")
    end

    private

    def self.fetch_bases(offset = nil)
      # Note: No rate limiting here as this is a global API call, not base-specific
      url = "#{META_API_URL}/bases"
      url += "?offset=#{offset}" if offset
      AirtableService.get(url)
    end
  end

  class Records
    def self.list(base_id:, table_id:, offset: nil)
      RateLimiterService::Airtable(base_id).wait_turn
      
      url = "#{API_URL}/#{base_id}/#{table_id}"
      url += "?offset=#{offset}" if offset
      
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
      RateLimiterService::Airtable(base_id).wait_turn
      
      url = "#{API_URL}/bases/#{base_id}/webhooks"
      
      body = {
        specification: specification
      }
      body[:notificationUrl] = notification_url if notification_url

      AirtableService.post(url, body)
    end

    def self.delete(base_id:, webhook_id:)
      RateLimiterService::Airtable(base_id).wait_turn
      
      url = "#{API_URL}/bases/#{base_id}/webhooks/#{webhook_id}"
      AirtableService.delete(url)
    end

    def self.refresh(base_id:, webhook_id:)
      RateLimiterService::Airtable(base_id).wait_turn
      
      url = "#{API_URL}/bases/#{base_id}/webhooks/#{webhook_id}/refresh"
      AirtableService.post(url, nil)
    end

    def self.payloads(base_id:, webhook_id:, start_cursor: nil)
      RateLimiterService::Airtable(base_id).wait_turn
      
      url = "#{API_URL}/bases/#{base_id}/webhooks/#{webhook_id}/payloads"
      url += "?cursor=#{start_cursor}" if start_cursor
      
      AirtableService.get(url)
    end
  end
end
