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

ActiveRecord::Schema[8.0].define(version: 2025_11_02_143504) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "field_value_baselines", force: :cascade do |t|
    t.bigint "sync_source_id", null: false
    t.string "row_id", null: false
    t.string "field_id", null: false
    t.jsonb "last_known_value"
    t.datetime "value_last_updated_at", null: false
    t.datetime "last_checked_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "first_seen_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.integer "checked_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["last_checked_at"], name: "idx_field_value_baselines_last_checked_at"
    t.index ["sync_source_id", "row_id", "field_id"], name: "index_field_value_baselines_on_sync_source_row_field", unique: true
    t.index ["sync_source_id"], name: "index_field_value_baselines_on_sync_source_id"
    t.index ["value_last_updated_at"], name: "index_field_value_baselines_on_value_last_updated_at"
  end

  create_table "sync_sources", force: :cascade do |t|
    t.string "source", null: false
    t.string "source_id", null: false
    t.jsonb "cursor"
    t.integer "poll_interval_seconds", default: 30, null: false
    t.float "poll_jitter", default: 0.1, null: false
    t.datetime "next_poll_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "last_poll_attempted_at"
    t.datetime "last_successful_poll_at"
    t.integer "consecutive_failures", default: 0, null: false
    t.jsonb "error_details", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.index ["next_poll_at"], name: "index_sync_sources_on_next_poll_at"
    t.index ["source", "source_id"], name: "index_sync_sources_on_source_and_source_id", unique: true
  end

  add_foreign_key "field_value_baselines", "sync_sources"
end
