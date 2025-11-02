class ConvertLoopsOutboxEnvelopeStatusToEnum < ActiveRecord::Migration[8.0]
  def up
    # Create PostgreSQL enum type
    execute <<-SQL
      CREATE TYPE loops_outbox_envelope_status AS ENUM (
        'queued',
        'sent',
        'ignored_noop',
        'failed',
        'partially_sent'
      );
    SQL

    # Add new column with enum type
    add_column :loops_outbox_envelopes, :status_new, :loops_outbox_envelope_status, null: false, default: 'queued'

    # Migrate data from integer to enum
    execute <<-SQL
      UPDATE loops_outbox_envelopes
      SET status_new = CASE status
        WHEN 0 THEN 'queued'::loops_outbox_envelope_status
        WHEN 1 THEN 'sent'::loops_outbox_envelope_status
        WHEN 2 THEN 'ignored_noop'::loops_outbox_envelope_status
        WHEN 3 THEN 'failed'::loops_outbox_envelope_status
        WHEN 4 THEN 'partially_sent'::loops_outbox_envelope_status
        ELSE 'queued'::loops_outbox_envelope_status
      END;
    SQL

    # Remove old integer column
    remove_column :loops_outbox_envelopes, :status

    # Rename new column to status
    rename_column :loops_outbox_envelopes, :status_new, :status

    # Recreate indexes (they were dropped when we removed the column)
    add_index :loops_outbox_envelopes, [:email_normalized, :status], 
              name: "index_loops_outbox_envelopes_on_email_normalized_and_status"
    add_index :loops_outbox_envelopes, :status
  end

  def down
    # Add integer column back
    add_column :loops_outbox_envelopes, :status_int, :integer, null: false, default: 0

    # Migrate data from enum to integer
    execute <<-SQL
      UPDATE loops_outbox_envelopes
      SET status_int = CASE status::text
        WHEN 'queued' THEN 0
        WHEN 'sent' THEN 1
        WHEN 'ignored_noop' THEN 2
        WHEN 'failed' THEN 3
        WHEN 'partially_sent' THEN 4
        ELSE 0
      END;
    SQL

    # Remove enum column
    remove_column :loops_outbox_envelopes, :status

    # Rename integer column back
    rename_column :loops_outbox_envelopes, :status_int, :status

    # Recreate indexes
    add_index :loops_outbox_envelopes, [:email_normalized, :status], 
              name: "index_loops_outbox_envelopes_on_email_normalized_and_status"
    add_index :loops_outbox_envelopes, :status

    # Drop enum type
    execute "DROP TYPE IF EXISTS loops_outbox_envelope_status;"
  end
end

