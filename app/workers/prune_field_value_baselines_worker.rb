class PruneFieldValueBaselinesWorker
  include Sidekiq::Worker

  sidekiq_options queue: :default

  # Default pruning window: 30 days (conservative margin beyond slowest poll interval)
  DEFAULT_PRUNING_WINDOW_DAYS = 30

  def perform(pruning_window_days = nil)
    cutoff = (pruning_window_days || DEFAULT_PRUNING_WINDOW_DAYS).days.ago
    
    # Perform deletion and capture actual count of deleted records
    deleted_count = FieldValueBaseline.prune_stale(older_than: cutoff)
    
    # Log the pruning operation
    Rails.logger.info("Pruned #{deleted_count} stale field value baselines older than #{cutoff}")
    
    deleted_count
  end
end

