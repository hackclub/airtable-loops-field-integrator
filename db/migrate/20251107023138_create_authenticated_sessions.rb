class CreateAuthenticatedSessions < ActiveRecord::Migration[8.0]
  def change
    create_table :authenticated_sessions do |t|
      t.string :email_normalized, null: false
      t.string :token, null: false
      t.datetime :expires_at, null: false

      t.timestamps
    end

    add_index :authenticated_sessions, :token, unique: true
    add_index :authenticated_sessions, :email_normalized
    add_index :authenticated_sessions, :expires_at
  end
end
