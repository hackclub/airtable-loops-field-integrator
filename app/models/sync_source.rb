class SyncSource < ApplicationRecord
  include Pollable

  self.inheritance_column = :source

  # Default to active rows everywhere
  default_scope { where(deleted_at: nil) }

  # Opt-in scope variants
  scope :with_deleted, -> { unscope(where: :deleted_at) }
  scope :only_deleted, -> { unscope(where: :deleted_at).where.not(deleted_at: nil) }

  validates :source, :source_id, presence: true
  # With partial unique index in DB; keep app-level validation aligned
  validates :source_id,
    uniqueness: {
      scope: :source,
      conditions: -> { where(deleted_at: nil) },
      message: "already has a sync source"
    }
  enum :source, { airtable: "airtable" } # add other sources as needed

  # PostgreSQL enum for deleted_reason
  enum :deleted_reason, {
    disappeared: "disappeared",
    manual: "manual",
    ignored_pattern: "ignored_pattern"
  }

  has_many :field_value_baselines, dependent: :destroy

  # Map source values to class names for STI
  def self.find_sti_class(source_value)
    case source_value
    when "airtable"
      AirtableSyncSource
    else
      super
    end
  end

  def self.sti_name
    case name
    when "AirtableSyncSource"
      "airtable"
    else
      super
    end
  end

  # Returns display name from metadata or source_id fallback
  def humanized_name
    display_name ||
      metadata["display_name"] ||
      metadata["name"] ||
      metadata["base_name"] ||
      source_id
  end

  # Convenience helpers
  def soft_delete!(reason:)
    update_columns(deleted_at: Time.current, deleted_reason: reason, updated_at: Time.current)
  end

  def restore!
    update_columns(deleted_at: nil, deleted_reason: nil, updated_at: Time.current)
  end
end
