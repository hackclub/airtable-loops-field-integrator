class Webhook < ApplicationRecord
  validates :base_id, :notification_url, :specification, presence: true
  validates :id, :mac_secret_base64, :expiration_time, presence: true, on: :update

  before_create :create_webhook_in_airtable
  before_destroy :delete_webhook_from_airtable

  scope :unexpired, -> { where('expiration_time > ?', Time.current) }
  scope :for_base, ->(base_id) { where(base_id: base_id) }

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
  end
end
