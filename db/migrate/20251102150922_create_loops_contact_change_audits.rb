class CreateLoopsContactChangeAudits < ActiveRecord::Migration[8.0]
  def change
    create_table :loops_contact_change_audits do |t|
      t.datetime :occurred_at, null: false
      t.string :email_normalized, null: false
      t.string :field_name, null: false
      t.jsonb :former_loops_value  # value in Loops before update
      t.jsonb :new_loops_value  # value sent to Loops
      t.jsonb :former_airtable_value  # value in Airtable before change
      t.jsonb :new_airtable_value  # value in Airtable after change
      t.string :strategy  # :upsert or :override
      t.references :sync_source, null: false, foreign_key: true
      t.string :table_id  # Airtable table ID
      t.string :record_id  # Airtable record ID
      t.string :airtable_field_id  # Airtable field ID
      t.string :request_id  # Loops API request ID for tracing

      t.timestamps
    end

    # Indexes for efficient querying
    add_index :loops_contact_change_audits, :email_normalized
    add_index :loops_contact_change_audits, :occurred_at
    # sync_source_id index is already created by t.references above
    add_index :loops_contact_change_audits, [ :email_normalized, :occurred_at ]
  end
end
