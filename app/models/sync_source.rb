class SyncSource < ApplicationRecord
  include Pollable

  self.inheritance_column = :source

  validates :source, :source_id, presence: true
  enum :source, { airtable: "airtable" } # add other sources as needed

  attribute :last_modified_field_name, :string

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
end


