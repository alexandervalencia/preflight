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

ActiveRecord::Schema[8.1].define(version: 2026_03_10_202500) do
  create_table "inline_comments", force: :cascade do |t|
    t.text "body", null: false
    t.string "commit_sha"
    t.datetime "created_at", null: false
    t.integer "line_number", null: false
    t.string "path", null: false
    t.integer "pull_request_id", null: false
    t.string "side", null: false
    t.datetime "updated_at", null: false
    t.index ["pull_request_id"], name: "index_inline_comments_on_pull_request_id"
  end

  create_table "pull_requests", force: :cascade do |t|
    t.string "base_branch", null: false
    t.datetime "created_at", null: false
    t.text "description", default: "", null: false
    t.string "source_branch", null: false
    t.datetime "updated_at", null: false
  end

  create_table "viewed_files", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "last_viewed_commit_sha", null: false
    t.string "path", null: false
    t.integer "pull_request_id", null: false
    t.datetime "updated_at", null: false
    t.index ["pull_request_id", "path"], name: "index_viewed_files_on_pull_request_id_and_path", unique: true
    t.index ["pull_request_id"], name: "index_viewed_files_on_pull_request_id"
  end

  add_foreign_key "inline_comments", "pull_requests"
  add_foreign_key "viewed_files", "pull_requests"
end
