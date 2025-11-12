class ConvertDeletedReasonToEnum < ActiveRecord::Migration[8.0]
  def up
    # Create PostgreSQL enum type
    execute <<-SQL
      CREATE TYPE sync_source_deleted_reason AS ENUM (
        'disappeared',
        'manual',
        'ignored_pattern'
      );
    SQL

    # Add new column with enum type (must use execute for custom types)
    execute "ALTER TABLE sync_sources ADD COLUMN deleted_reason_new sync_source_deleted_reason;"

    # Migrate data from string to enum
    execute <<-SQL
      UPDATE sync_sources
      SET deleted_reason_new = CASE deleted_reason
        WHEN 'disappeared' THEN 'disappeared'::sync_source_deleted_reason
        WHEN 'manual' THEN 'manual'::sync_source_deleted_reason
        WHEN 'ignored_pattern' THEN 'ignored_pattern'::sync_source_deleted_reason
        ELSE NULL
      END;
    SQL

    # Remove old string column
    remove_column :sync_sources, :deleted_reason

    # Rename new column to deleted_reason
    rename_column :sync_sources, :deleted_reason_new, :deleted_reason
  end

  def down
    # Add string column back
    add_column :sync_sources, :deleted_reason_str, :string

    # Migrate data from enum to string
    execute <<-SQL
      UPDATE sync_sources
      SET deleted_reason_str = deleted_reason::text;
    SQL

    # Remove enum column
    remove_column :sync_sources, :deleted_reason

    # Rename string column back
    rename_column :sync_sources, :deleted_reason_str, :deleted_reason

    # Drop enum type
    execute "DROP TYPE IF EXISTS sync_source_deleted_reason;"
  end
end
