class SyncSource < ApplicationRecord
  include Pollable

  validates :source, :source_id, presence: true
  enum :source, { airtable: "airtable" } # add other sources as needed
end


