require 'httpx'
require 'json'

class AiService
  API_KEY = Rails.application.credentials.openai.api_key
  MODEL = "o3-mini"

  class << self
    def prompt_structured(prompt, output:)
      # Convert Ruby types to JSON schema types
      json_schema = {
        type: "object",
        properties: convert_ruby_types_to_schema(output),
        required: output.keys,
        additionalProperties: false
      }

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

      JSON.parse(content)
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
