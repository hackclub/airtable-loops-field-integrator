module Poller
  def self.for(sync_source)
    case sync_source
    when AirtableSyncSource then Pollers::AirtableToLoops.new
    else
      raise "Unknown sync source type: #{sync_source.class.name}"
    end
  end
end


