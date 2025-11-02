class FieldValueBaseline < ApplicationRecord
  belongs_to :sync_source

  validates :sync_source_id, :row_id, :field_id, :last_checked_at, presence: true

  scope :stale_before, ->(time) { where("last_checked_at < ?", time) }
  scope :for_sync_source, ->(source) { where(sync_source_id: source.id) }

  # One-shot detect + persist (baseline on first see; update if changed)
  # This is the single public API method for using this model
  #
  # @param sync_source [SyncSource] The sync source this baseline belongs to
  # @param row_id [String] Combined table_id and record_id (e.g., "tbl123_rec456")
  # @param field_id [String] The Airtable field ID
  # @param current_value [Object] The current field value from Airtable
  # @param checked_at [Time] When this check occurred (defaults to Time.current)
  # @return [Hash] Returns { baseline:, changed:, first_time: }
  #   - baseline: The FieldValueBaseline record (persisted)
  #   - changed: Boolean indicating if value changed from last known value
  #   - first_time: Boolean indicating if this is the first time seeing this row+field
  def self.detect_change(sync_source:, row_id:, field_id:, current_value:, checked_at: Time.current)
    bl = find_or_initialize_by(
      sync_source_id: sync_source.id,
      row_id: row_id,
      field_id: field_id
    )
    first_time = bl.new_record?

    if first_time
      changed = true
    else
      changed = bl.send(:value_changed?, current_value)
    end

    if first_time
      bl.last_known_value = bl.send(:canonicalize, current_value)
      bl.value_last_updated_at = checked_at
      bl.first_seen_at ||= checked_at if bl.respond_to?(:first_seen_at)
    elsif changed
      bl.last_known_value = bl.send(:canonicalize, current_value)
      bl.value_last_updated_at = checked_at
    end

    bl.last_checked_at = checked_at
    bl.first_seen_at ||= checked_at if bl.respond_to?(:first_seen_at)
    bl.checked_count = (bl.checked_count || 0) + 1 if bl.respond_to?(:checked_count)
    bl.save! if bl.changed? || bl.new_record?

    { baseline: bl, changed: changed, first_time: first_time }
  end

  # Admin/cron helper to purge stale entries
  # @param older_than [Time] Delete baselines not checked since this time
  # @return [Integer] Number of records deleted
  def self.prune_stale(older_than:)
    stale_before(older_than).in_batches.delete_all
  end

  private

  # Compare new value against baseline (uses canonicalize for JSONB comparison)
  def value_changed?(new_value)
    # Compare canonicalized JSON representations (handles nil properly)
    canonicalize(new_value).to_json != canonicalize(last_known_value).to_json
  end

  # Keep this lightweight and consistent for hashing/compare
  def canonicalize(obj)
    case obj
    when Hash
      obj.keys.sort.each_with_object({}) { |k, h| h[k.to_s] = canonicalize(obj[k]) }
    when Array
      obj.map { |v| canonicalize(v) }
    else
      obj
    end
  end
end

