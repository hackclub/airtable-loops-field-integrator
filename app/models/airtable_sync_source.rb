class AirtableSyncSource < SyncSource
  after_initialize :set_defaults, if: :new_record?

  private

  def set_defaults
    self.source ||= "airtable"
    self.metadata ||= {}
  end
end

