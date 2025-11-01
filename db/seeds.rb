# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

SyncSource.find_or_create_by!(source: "airtable", source_id: "appXXXXXXXXXXXX") do |s|
  s.last_modified_field_id = "fldYYYYYYYYYYYY"
  s.poll_interval_seconds  = 30 # per-base cadence (can vary per row)
  s.next_poll_at           = Time.current
end
