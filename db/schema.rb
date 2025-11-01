# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_11_01_195637) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "sync_sources", force: :cascade do |t|
    t.string "source", null: false
    t.string "source_id", null: false
    t.string "cursor"
    t.string "last_modified_field_name"
    t.integer "poll_interval_seconds", default: 30, null: false
    t.float "poll_jitter", default: 0.1, null: false
    t.datetime "next_poll_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "last_poll_attempted_at"
    t.datetime "last_successful_poll_at"
    t.integer "consecutive_failures", default: 0, null: false
    t.jsonb "error_details", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["next_poll_at"], name: "index_sync_sources_on_next_poll_at"
    t.index ["source", "source_id"], name: "index_sync_sources_on_source_and_source_id", unique: true
  end
end
