class RemoveTypeFromSyncSources < ActiveRecord::Migration[8.0]
  def change
    remove_column :sync_sources, :type, :string
  end
end
