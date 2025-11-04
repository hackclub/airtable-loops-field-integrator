class CreateLoopsOutboxEnvelopes < ActiveRecord::Migration[8.0]
  def change
    create_table :loops_outbox_envelopes do |t|
      t.string :email_normalized, null: false
      t.jsonb :payload, null: false  # envelope with field_name => {value, strategy, modified_at}
      t.integer :status, null: false, default: 0  # enum: queued=0, sent=1, ignored_noop=2, failed=3, partially_sent=4
      t.jsonb :provenance, null: false, default: {}  # sync_source_id, table_id, record_id, fields array
      t.jsonb :error, default: {}  # error details if failed
      t.references :sync_source, null: true, foreign_key: true  # optional reference
      
      t.timestamps
    end

    # Index for batching by email and status
    add_index :loops_outbox_envelopes, [:email_normalized, :status], 
              name: "index_loops_outbox_envelopes_on_email_normalized_and_status"
    
    # Index on status for filtering queued envelopes
    add_index :loops_outbox_envelopes, :status
    
    # Index on created_at for pruning
    add_index :loops_outbox_envelopes, :created_at
  end
end

