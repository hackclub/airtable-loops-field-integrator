class CreateFieldValueBaselines < ActiveRecord::Migration[8.0]
  def change
    create_table :field_value_baselines do |t|
      # Core columns
      t.references :sync_source, null: false, foreign_key: true
      t.string :row_id, null: false  # combination of table_id + record_id for AirtableSyncSource
      t.string :field_id, null: false  # Airtable field ID for AirtableSyncSource
      t.jsonb :last_known_value  # the baseline field value (nullable)
      t.datetime :value_last_updated_at, null: false  # when baseline value was last updated

      # Heartbeat (required)
      t.datetime :last_checked_at, null: false, default: -> { "CURRENT_TIMESTAMP" }

      # Optional analytics (nice to have)
      t.datetime :first_seen_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.integer :checked_count, null: false, default: 0

      t.timestamps
    end

    # Unique index on [sync_source_id, row_id, field_id] for uniqueness
    add_index :field_value_baselines, [:sync_source_id, :row_id, :field_id], 
              unique: true, 
              name: "index_field_value_baselines_on_sync_source_row_field"

    # Index on last_checked_at for pruning stale entries
    add_index :field_value_baselines, :last_checked_at, 
              name: "idx_field_value_baselines_last_checked_at"

    # Index on value_last_updated_at for change tracking
    add_index :field_value_baselines, :value_last_updated_at

    # Note: sync_source_id index is already created by t.references above
  end
end

