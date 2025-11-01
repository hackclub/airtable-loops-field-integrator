class AirtableSyncSource < SyncSource
  after_initialize :set_defaults, if: :new_record?

  private

  def set_defaults
    self.source ||= "airtable"
    self.last_modified_field_name ||= 'Loops - Last Modified'
  end
end

