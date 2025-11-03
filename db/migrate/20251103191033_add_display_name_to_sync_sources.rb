class AddDisplayNameToSyncSources < ActiveRecord::Migration[8.0]
  def change
    add_column :sync_sources, :display_name, :string
    add_column :sync_sources, :display_name_updated_at, :datetime
  end
end
