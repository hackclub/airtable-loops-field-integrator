class CreateLoopsFieldBaselines < ActiveRecord::Migration[8.0]
  def change
    create_table :loops_field_baselines do |t|
      t.string :email_normalized, null: false
      t.string :field_name, null: false
      t.jsonb :last_sent_value  # last value sent to Loops
      t.datetime :last_sent_at
      t.datetime :expires_at  # TTL for baseline (default 90 days)

      t.timestamps
    end

    # Unique index on email + field_name for efficient lookups
    add_index :loops_field_baselines, [ :email_normalized, :field_name ],
              unique: true,
              name: "index_loops_field_baselines_on_email_normalized_and_field_name"

    # Index on expires_at for pruning
    add_index :loops_field_baselines, :expires_at
  end
end
