class CreateSyncSources < ActiveRecord::Migration[8.0]
  def change
    create_table :sync_sources do |t|
      t.string  :source,    null: false      # e.g., "airtable"
      t.string  :source_id, null: false      # e.g., Airtable base id
      t.string  :cursor                         # watermark / last-modified token
      t.string  :last_modified_field_id         # Airtable last-modified field id
      t.integer :poll_interval_seconds, null: false, default: 30
      t.float   :poll_jitter,           null: false, default: 0.10
      t.datetime :next_poll_at,         null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.datetime :last_poll_attempted_at
      t.datetime :last_successful_poll_at
      t.integer  :consecutive_failures, null: false, default: 0
      t.jsonb    :error_details,        null: false, default: {}
      t.timestamps
    end
    add_index :sync_sources, [:source, :source_id], unique: true
    add_index :sync_sources, :next_poll_at
  end
end


