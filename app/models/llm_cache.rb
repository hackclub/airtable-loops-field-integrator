class LlmCache < ApplicationRecord
  # Default pruning window: 90 days
  DEFAULT_PRUNING_WINDOW_DAYS = 90

  # Default max cache size: 512 MB
  DEFAULT_MAX_CACHE_MB = 512

  # Get pruning window in days (ENV override: LLM_CACHE_PRUNING_WINDOW_DAYS)
  def self.pruning_window_days
    ENV.fetch("LLM_CACHE_PRUNING_WINDOW_DAYS", DEFAULT_PRUNING_WINDOW_DAYS).to_i
  end

  # Get max cache size in MB (ENV override: LLM_CACHE_MAX_MB)
  def self.max_cache_mb
    ENV.fetch("LLM_CACHE_MAX_MB", DEFAULT_MAX_CACHE_MB).to_i
  end

  # Calculate bytes size from jsonb columns
  def calculate_bytes_size
    request_size = ActiveRecord::Base.connection.execute(
      "SELECT pg_column_size(request_json) as size FROM llm_caches WHERE id = #{id}"
    ).first["size"]

    response_size = ActiveRecord::Base.connection.execute(
      "SELECT pg_column_size(response_json) as size FROM llm_caches WHERE id = #{id}"
    ).first["size"]

    request_size + response_size
  end

  # Update bytes_size after save
  before_save :calculate_and_set_bytes_size

  def calculate_and_set_bytes_size
    return unless persisted? || request_json.present? || response_json.present?

    self.bytes_size = calculate_bytes_size_from_values
  end

  def calculate_bytes_size_from_values
    request_size = request_json.present? ? request_json.to_json.bytesize : 0
    response_size = response_json.present? ? response_json.to_json.bytesize : 0
    request_size + response_size
  end

  # Touch last_used_at
  def touch_last_used!
    update_column(:last_used_at, Time.current)
  end
end
