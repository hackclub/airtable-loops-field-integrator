class PruneLlmCacheWorker
  include Sidekiq::Worker

  sidekiq_options queue: :default

  def perform
    cutoff = LlmCache.pruning_window_days.days.ago

    # Step 1: Delete rows older than the pruning window
    old_deleted = LlmCache.where("created_at < ?", cutoff).delete_all
    Rails.logger.info("PruneLlmCacheWorker: Deleted #{old_deleted} cache entries older than #{cutoff}")

    # Step 2: Check total cache size and prune if needed
    max_mb = LlmCache.max_cache_mb
    total_bytes = LlmCache.sum(:bytes_size)
    total_mb = total_bytes / (1024.0 * 1024.0)

    Rails.logger.info("PruneLlmCacheWorker: Current cache size: #{total_mb.round(2)} MB (limit: #{max_mb} MB)")

    if total_mb > max_mb
      # Delete oldest entries by last_used_at until under limit
      target_bytes = max_mb * 1024 * 1024
      deleted_count = 0

      loop do
        current_total = LlmCache.sum(:bytes_size)
        break if current_total <= target_bytes

        # Get oldest entry by last_used_at
        oldest = LlmCache.order(:last_used_at).limit(1).first
        break unless oldest

        entry_bytes = oldest.bytes_size
        oldest.delete
        deleted_count += 1

        Rails.logger.debug("PruneLlmCacheWorker: Deleted cache entry (prompt_hash=#{oldest.prompt_hash[0..16]}..., bytes=#{entry_bytes})")
      end

      final_total = LlmCache.sum(:bytes_size)
      final_mb = final_total / (1024.0 * 1024.0)

      Rails.logger.info(
        "PruneLlmCacheWorker: Pruned #{deleted_count} additional entries. " \
        "Final cache size: #{final_mb.round(2)} MB"
      )
    end

    { old_deleted: old_deleted, final_size_mb: (LlmCache.sum(:bytes_size) / (1024.0 * 1024.0)).round(2) }
  end
end
