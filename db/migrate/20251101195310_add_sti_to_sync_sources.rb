class AddStiToSyncSources < ActiveRecord::Migration[8.0]
  def change
    add_column :sync_sources, :type, :string
    rename_column :sync_sources, :last_modified_field_id, :last_modified_field_name
  end
end
