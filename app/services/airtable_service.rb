class AirtableService
  API_TOKEN = Rails.application.credentials.airtable_personal_access_token
  API_URL = "https://api.airtable.com/v0/meta"

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
      url = "#{API_URL}/bases"
      url += "?offset=#{offset}" if offset

      response = HTTPX.with(
        headers: {
          "Authorization" => "Bearer #{API_TOKEN}"
        }
      ).get(url)
      
      unless response.status == 200
        raise "Airtable API error: #{response.status} - #{response.body.to_s}"
      end

      response.json
    end
  end
end
