class SyncSource < ApplicationRecord
  include Pollable

  self.inheritance_column = :source

  validates :source, :source_id, presence: true
  validates :source_id, uniqueness: { scope: :source, message: "already has a sync source" }
  enum :source, { airtable: "airtable" } # add other sources as needed

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
end
