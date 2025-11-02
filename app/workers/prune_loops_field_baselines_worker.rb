class PruneLoopsFieldBaselinesWorker
  include Sidekiq::Worker

  sidekiq_options queue: :default

  # Default pruning window: 90 days (matches expires_at TTL)
  DEFAULT_PRUNING_WINDOW_DAYS = 90

  def perform(pruning_window_days = nil)
    cutoff = (pruning_window_days || DEFAULT_PRUNING_WINDOW_DAYS).days.ago
    
    # Delete expired baselines (where expires_at < cutoff)
    deleted_count = LoopsFieldBaseline.where("expires_at < ?", cutoff).in_batches.delete_all
    
    # Log the pruning operation
    Rails.logger.info("Pruned #{deleted_count} expired loops field baselines older than #{cutoff}")
    
    deleted_count
  end
end

