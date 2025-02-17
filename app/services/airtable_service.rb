class AirtableService
  API_TOKEN = Rails.application.credentials.airtable_personal_access_token
  API_URL = "https://api.airtable.com/v0"
  META_API_URL = "#{API_URL}/meta"

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

      debugger if response.class == HTTPX::Response

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

    private

    def self.fetch_bases(offset = nil)
      url = "#{META_API_URL}/bases"
      url += "?offset=#{offset}" if offset
      AirtableService.get(url)
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
  end
end
