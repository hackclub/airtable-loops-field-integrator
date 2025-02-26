class LoopsSpecialSetFullAddressJob < ApplicationJob
  class MissingAddressPartsError < StandardError; end

  # raw_name_text should be the full name of the person, or any other name details we have
  def perform(edit_timestamp, base_id, email, raw_address_text)
    parts = AiService.parse_full_address(raw_address_text)

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
