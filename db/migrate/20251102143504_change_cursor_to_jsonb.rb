class ChangeCursorToJsonb < ActiveRecord::Migration[8.0]
  def up
    # Change column type from string to jsonb
    # Convert string values to JSONB strings using to_jsonb
    change_column :sync_sources, :cursor, :jsonb, using: 'CASE WHEN cursor IS NULL THEN NULL ELSE to_jsonb(cursor::text) END'
  end

  def down
    # Convert JSONB back to string (extract the string value from JSONB)
    change_column :sync_sources, :cursor, :string, using: 'CASE WHEN cursor IS NULL THEN NULL ELSE cursor::text END'
  end
end
