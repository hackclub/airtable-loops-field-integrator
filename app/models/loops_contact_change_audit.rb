class LoopsContactChangeAudit < ApplicationRecord
  belongs_to :sync_source

  validates :occurred_at, :email_normalized, :field_name, :sync_source_id, presence: true

  scope :for_email, ->(email) { where(email_normalized: email) }
  scope :for_sync_source, ->(source) { where(sync_source_id: source.id) }
  scope :since, ->(time) { where("occurred_at >= ?", time) }
end

