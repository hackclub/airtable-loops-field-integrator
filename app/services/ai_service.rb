require 'httpx'
require 'json'

class AiService
  API_KEY = Rails.application.credentials.openai.api_key
  MODEL = "gpt-4o"
  
  class MissingAddressPartsError < StandardError; end

  class << self
    def prompt_structured(prompt, output:)
      # Convert Ruby types to JSON schema types
      json_schema = {
        type: "object",
        properties: convert_ruby_types_to_schema(output),
        required: output.keys,
        additionalProperties: false
      }

      cache_key = "ai_service/#{MODEL}/#{Digest::SHA256.hexdigest(prompt)}"

      Rails.cache.fetch(cache_key) do
        response = HTTPX.post(
          "https://api.openai.com/v1/chat/completions",
          headers: {
            "Content-Type" => "application/json",
            "Authorization" => "Bearer #{API_KEY}"
          },
          json: {
            model: MODEL,
            messages: [
              { role: "user", content: prompt }
            ],
            response_format: {
              type: "json_schema",
              json_schema: {
                name: "structured_output",
                schema: json_schema,
                strict: true
              }
            }
          }
        )

        raise response.body.to_s unless response.status == 200

        parsed_response = JSON.parse(response.body.to_s)
        content = parsed_response["choices"][0]["message"]["content"]
        
        # Handle potential refusal
        if parsed_response["choices"][0]["message"]["refusal"]
          raise parsed_response["choices"][0]["message"]["refusal"]
        end

        JSON.parse(content, symbolize_names: true)
      end
    end

    def parse_full_address(raw_address_text)
      prompt = <<~PROMPT
A user provided us with unstructured data for their mailing address. We need to break it into address_line_1, address_line_2 (optional), city, state_or_province, zip_or_postal_code, and country parts

1. Break the provided info into parts.
2. Strip unnecessary punctuation
3. Ensure that the parts, when combined, contain all of the user-provided text. Some countries have complicated address systems, and parts of address text that seem insignificant are crucial for mail to be delivered.
4. Do not invent anything in your returned address (ex. if the user didn't specify a country, don't list a country, and so on)
5. There is a maximum of 30 characters per part.

User provided info:

#{raw_address_text}
PROMPT

      parts = prompt_structured(
        prompt,
        output: {
          address_line_1: :string,
          address_line_2: :string,
          city: :string,
          state_or_province: :string,
          zip_or_postal_code: :string,
          country: :string,
        }
      )

      required_parts = [:address_line_1, :city, :state_or_province, :zip_or_postal_code, :country]
      missing_parts = required_parts.select { |part| parts[part].to_s.empty? }

      raise MissingAddressPartsError, "Missing required parts: #{missing_parts.join(', ')}" if missing_parts.any?

      parts
    end

    private

    def convert_ruby_types_to_schema(hash)
      schema = {}
      
      hash.each do |key, type|
        schema[key] = case type
        when :string
          { type: "string" }
        when :integer
          { type: "integer" }
        when :number, :float
          { type: "number" }
        when :boolean
          { type: "boolean" }
        when Array
          if type.length == 1
            {
              type: "array",
              items: convert_ruby_types_to_schema({ item: type[0] })[:item]
            }
          else
            raise "Array type must have exactly one element specifying the type of items"
          end
        when Hash
          {
            type: "object",
            properties: convert_ruby_types_to_schema(type),
            required: type.keys,
            additionalProperties: false
          }
        else
          raise "Unsupported type: #{type}"
        end
      end

      schema
    end
  end
end
