class SyncSourceEnqueuerWorker
  include Sidekiq::Worker

  sidekiq_options queue: :scheduler, retry: false

  BATCH_SIZE = 200

  def perform
    loop do
      due = []

      ApplicationRecord.transaction do
        due = SyncSource.where("next_poll_at <= ?", Time.current)
                        .order(:next_poll_at)
                        .limit(BATCH_SIZE)
                        .lock("FOR UPDATE SKIP LOCKED")
                        .to_a

        # Reserve immediately so other enqueuers (or the next tick) won't pick them again
        due.each { |s| s.reserve_from!(Time.current) }
      end

      break if due.empty?

      due.each { |s| SyncSourcePollWorker.perform_async(s.id) }
    end
  end
end


