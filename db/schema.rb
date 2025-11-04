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

ActiveRecord::Schema[8.0].define(version: 2025_11_03_191033) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  # Custom types defined in this database.
  # Note that some types may not work with other database engines. Be careful if changing database.
  create_enum "loops_outbox_envelope_status", ["queued", "sent", "ignored_noop", "failed", "partially_sent"]

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

  create_table "loops_contact_change_audits", force: :cascade do |t|
    t.datetime "occurred_at", null: false
    t.string "email_normalized", null: false
    t.string "field_name", null: false
    t.jsonb "former_loops_value"
    t.jsonb "new_loops_value"
    t.jsonb "former_sync_source_value"
    t.jsonb "new_sync_source_value"
    t.string "strategy"
    t.bigint "sync_source_id", null: false
    t.string "sync_source_table_id"
    t.string "sync_source_record_id"
    t.string "sync_source_field_id"
    t.string "request_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "provenance", default: {}
    t.index ["email_normalized", "occurred_at"], name: "idx_on_email_normalized_occurred_at_4255605731"
    t.index ["email_normalized"], name: "index_loops_contact_change_audits_on_email_normalized"
    t.index ["occurred_at"], name: "index_loops_contact_change_audits_on_occurred_at"
    t.index ["provenance"], name: "index_loops_contact_change_audits_on_provenance", using: :gin
    t.index ["sync_source_id"], name: "index_loops_contact_change_audits_on_sync_source_id"
  end

  create_table "loops_field_baselines", force: :cascade do |t|
    t.string "email_normalized", null: false
    t.string "field_name", null: false
    t.jsonb "last_sent_value"
    t.datetime "last_sent_at"
    t.datetime "expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email_normalized", "field_name"], name: "index_loops_field_baselines_on_email_normalized_and_field_name", unique: true
    t.index ["expires_at"], name: "index_loops_field_baselines_on_expires_at"
  end

  create_table "loops_outbox_envelopes", force: :cascade do |t|
    t.string "email_normalized", null: false
    t.jsonb "payload", null: false
    t.jsonb "provenance", default: {}, null: false
    t.jsonb "error", default: {}
    t.bigint "sync_source_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.enum "status", default: "queued", null: false, enum_type: "loops_outbox_envelope_status"
    t.index ["created_at"], name: "index_loops_outbox_envelopes_on_created_at"
    t.index ["email_normalized", "status"], name: "index_loops_outbox_envelopes_on_email_normalized_and_status"
    t.index ["status"], name: "index_loops_outbox_envelopes_on_status"
    t.index ["sync_source_id"], name: "index_loops_outbox_envelopes_on_sync_source_id"
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
    t.string "display_name"
    t.datetime "display_name_updated_at"
    t.index ["next_poll_at"], name: "index_sync_sources_on_next_poll_at"
    t.index ["source", "source_id"], name: "index_sync_sources_on_source_and_source_id", unique: true
  end

  add_foreign_key "field_value_baselines", "sync_sources"
  add_foreign_key "loops_contact_change_audits", "sync_sources"
  add_foreign_key "loops_outbox_envelopes", "sync_sources"
end
