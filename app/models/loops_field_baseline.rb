class LoopsFieldBaseline < ApplicationRecord
  validates :email_normalized, :field_name, presence: true
  validates :email_normalized, uniqueness: { scope: :field_name }

  scope :expired, -> { where("expires_at < ?", Time.current) }

  # Find or create a baseline for a given email and field
  def self.find_or_create_baseline(email_normalized:, field_name:)
    find_or_initialize_by(
      email_normalized: email_normalized,
      field_name: field_name
    )
  end

  # Update baseline with new sent value
  def update_sent_value(value:, expires_in_days: 90)
    self.last_sent_value = value
    self.last_sent_at = Time.current
    self.expires_at = Time.current + expires_in_days.days
    save!
  end
end

