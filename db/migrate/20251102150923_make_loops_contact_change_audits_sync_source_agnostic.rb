class MakeLoopsContactChangeAuditsSyncSourceAgnostic < ActiveRecord::Migration[8.0]
  def change
    # Rename Airtable-specific columns to generic sync source columns
    rename_column :loops_contact_change_audits, :former_airtable_value, :former_sync_source_value
    rename_column :loops_contact_change_audits, :new_airtable_value, :new_sync_source_value

    # Rename Airtable-specific identifiers to generic sync source identifiers
    rename_column :loops_contact_change_audits, :table_id, :sync_source_table_id
    rename_column :loops_contact_change_audits, :record_id, :sync_source_record_id
    rename_column :loops_contact_change_audits, :airtable_field_id, :sync_source_field_id

    # Add generic provenance jsonb column for sync-source-specific metadata
    # This allows storing Airtable-specific data (table_id, record_id, field_id)
    # or other sync source types' specific identifiers
    add_column :loops_contact_change_audits, :provenance, :jsonb, default: {}

    # Add index on provenance for querying
    add_index :loops_contact_change_audits, :provenance, using: :gin
  end
end
