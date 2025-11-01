module Poller
  def self.for(sync_source)
    case sync_source.source
    when "airtable" then Pollers::AirtableToLoops.new
    else
      raise "Unknown source: #{sync_source.source.inspect}"
    end
  end
end


