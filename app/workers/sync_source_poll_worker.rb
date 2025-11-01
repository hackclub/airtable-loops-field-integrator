class SyncSourcePollWorker
  include Sidekiq::Worker

  sidekiq_options queue: :polling

  def perform(id)
    s = SyncSource.find_by(id: id)
    return unless s

    s.mark_attempt!

    begin
      Poller.for(s).call(s)   # <-- this invokes your per-source logic
      s.mark_success!
    rescue => e
      s.mark_failure!(message: e.message, klass: e.class.name, at: Time.current)
      raise
    end
  end
end


