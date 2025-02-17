class CreateWebhooks < ActiveRecord::Migration[8.0]
  def change
    create_table :webhooks, id: false do |t|
      t.string :id, primary_key: true
      t.string :base_id
      t.string :notification_url
      t.json :specification
      t.string :mac_secret_base64
      t.datetime :expiration_time

      t.timestamps
    end
  end
end
