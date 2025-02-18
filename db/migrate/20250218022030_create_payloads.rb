class CreatePayloads < ActiveRecord::Migration[8.0]
  def change
    create_table :payloads do |t|
      t.string :base_id
      t.references :webhook, null: false, foreign_key: true, type: :string
      t.json :body

      t.timestamps
    end
  end
end
