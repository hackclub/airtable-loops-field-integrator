class LoopsSpecialSetFullAddressJob < ApplicationJob
  class MissingAddressPartsError < StandardError; end

  # raw_name_text should be the full name of the person, or any other name details we have
  def perform(edit_timestamp, base_id, email, raw_address_text)
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

    parts = AiService.prompt_structured(
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

    LoopsUpdateFieldJob.set(priority: edit_timestamp.to_i).perform_later(base_id, email, {
      addressLine1: parts.fetch(:address_line_1, ""),
      addressLine2: parts.fetch(:address_line_2, ""),
      addressCity: parts.fetch(:city, ""),
      addressState: parts.fetch(:state_or_province, ""),
      addressZipCode: parts.fetch(:zip_or_postal_code, ""),
      addressCountry: parts.fetch(:country, ""),
      addressLastUpdatedAt: edit_timestamp,
    })
  end
end
