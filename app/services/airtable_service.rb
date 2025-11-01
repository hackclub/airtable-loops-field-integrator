class AirtableService
  API_URL = "https://api.airtable.com/v0"
  META_API_URL = "#{API_URL}/meta"

  def self.api_token
    ENV.fetch("AIRTABLE_PERSONAL_ACCESS_TOKEN")
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

    def delete(url)
      make_request(:delete, url)
    end

    private

    def make_request(method, url, body: nil)
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

    private

    def self.fetch_bases(offset = nil)
      url = "#{META_API_URL}/bases"
      url += "?offset=#{offset}" if offset
      AirtableService.get(url)
    end
  end

  class Records
    def self.list(base_id:, table_id:, offset: nil)
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

