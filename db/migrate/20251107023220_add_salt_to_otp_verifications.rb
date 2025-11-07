class AddSaltToOtpVerifications < ActiveRecord::Migration[8.0]
  def change
    add_column :otp_verifications, :salt, :string, null: false
  end
end
