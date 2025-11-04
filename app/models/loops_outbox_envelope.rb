class LoopsOutboxEnvelope < ApplicationRecord
  belongs_to :sync_source, optional: true

  # PostgreSQL enum - no integer mapping needed, PostgreSQL handles it
  enum :status, {
    queued: "queued",
    sent: "sent",
    ignored_noop: "ignored_noop",
    failed: "failed",
    partially_sent: "partially_sent"
  }

  validates :email_normalized, :payload, :provenance, presence: true
  validates :status, presence: true

  scope :queued, -> { where(status: :queued) }
  scope :sent, -> { where(status: :sent) }
  scope :failed, -> { where(status: :failed) }
  scope :for_email, ->(email) { where(email_normalized: email) }
end

