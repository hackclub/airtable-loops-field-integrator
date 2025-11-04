class PruneLoopsOutboxWorker
  include Sidekiq::Worker

  sidekiq_options queue: :default

  # Default retention period: 30 days
  DEFAULT_RETENTION_DAYS = 30

  def perform(retention_days = nil)
    cutoff = (retention_days || DEFAULT_RETENTION_DAYS).days.ago
    
    # Delete envelopes that are sent/ignored_noop/failed/partially_sent and older than retention period
    deleted_count = LoopsOutboxEnvelope.where(
      status: [:sent, :ignored_noop, :failed, :partially_sent]
    ).where("created_at < ?", cutoff).in_batches.delete_all
    
    # Log the pruning operation
    Rails.logger.info("Pruned #{deleted_count} old loops outbox envelopes older than #{cutoff}")
    
    deleted_count
  end
end

