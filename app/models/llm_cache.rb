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

  # Update bytes_size before save
  before_save :calculate_and_set_bytes_size

  def calculate_and_set_bytes_size
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
