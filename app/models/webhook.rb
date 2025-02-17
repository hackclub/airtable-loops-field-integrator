class Webhook < ApplicationRecord
  include GlobalID::Identification

  validates :base_id, :notification_url, :specification, presence: true
  validates :id, :mac_secret_base64, :expiration_time, presence: true, on: :update

  before_create :create_webhook_in_airtable
  before_destroy :delete_webhook_from_airtable

  scope :unexpired, -> { where('expiration_time > ?', Time.current) }
  scope :for_base, ->(base_id) { where(base_id: base_id) }

  def find_each_new_payload(&block)
    return enum_for(:find_each_new_payload) unless block_given?

    cursor = last_cursor
    final_cursor = nil

    loop do
      response = AirtableService::Webhooks.payloads(
        base_id: base_id,
        webhook_id: id,
        start_cursor: cursor
      )

      response["payloads"].each(&block)
      
      final_cursor = response["cursor"]
      break unless response["mightHaveMore"]
      cursor = response["cursor"]
    end

    # Only update the cursor after all payloads have been processed successfully
    update!(last_cursor: final_cursor) if final_cursor
  end

  def refresh!
    response = AirtableService::Webhooks.refresh(
      base_id: base_id,
      webhook_id: id
    )

    if response["expirationTime"]
      update!(expiration_time: Time.parse(response["expirationTime"]))
    else
      raise "Webhook refresh failed: No expiration time received"
    end
  end

  private

  def create_webhook_in_airtable
    response = AirtableService::Webhooks.create(
      base_id: base_id,
      notification_url: notification_url,
      specification: specification
    )

    # Set the fields from Airtable's response
    self.id = response["id"]
    self.mac_secret_base64 = response["macSecretBase64"]
    self.expiration_time = Time.parse(response["expirationTime"]) if response["expirationTime"]

    # If any required fields are missing from the response, add an error
    errors.add(:base, "Invalid Airtable response") unless id.present? && mac_secret_base64.present?
    
    # Prevent save if we have errors
    throw(:abort) if errors.any?
  end

  def delete_webhook_from_airtable
    AirtableService::Webhooks.delete(
      base_id: base_id,
      webhook_id: id
    )
  rescue => e
    Rails.logger.error "Failed to delete webhook from Airtable: #{e.message}"
    # Don't prevent the local record from being deleted even if the API call fails
    # The webhook might already be deleted or expired in Airtable
  end
end
