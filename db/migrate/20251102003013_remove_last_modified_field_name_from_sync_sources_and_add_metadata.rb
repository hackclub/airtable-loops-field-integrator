class RemoveLastModifiedFieldNameFromSyncSourcesAndAddMetadata < ActiveRecord::Migration[8.0]
  def change
    remove_column :sync_sources, :last_modified_field_name, :string
    add_column :sync_sources, :metadata, :jsonb, null: false, default: {}
  end
end
