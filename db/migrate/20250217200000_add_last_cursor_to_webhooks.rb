class AddLastCursorToWebhooks < ActiveRecord::Migration[8.0]
  def change
    add_column :webhooks, :last_cursor, :integer
  end
end 