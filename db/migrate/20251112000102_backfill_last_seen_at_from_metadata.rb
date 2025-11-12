class BackfillLastSeenAtFromMetadata < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      UPDATE sync_sources
      SET last_seen_at = (metadata->>'last_seen_at')::timestamptz
      WHERE last_seen_at IS NULL
        AND metadata ? 'last_seen_at';
    SQL
  end

  def down
    # No-op: backfill is not reversible
  end
end
