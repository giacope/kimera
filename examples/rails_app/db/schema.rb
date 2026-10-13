ActiveRecord::Schema[8.1].define(version: 2026_10_01_000000) do
  create_table "accounts", force: :cascade do |t|
    t.string "email", null: false
    t.integer "credit_cents", default: 0, null: false
    t.boolean "suspended", default: false, null: false
    t.string "api_token"
    t.timestamps
  end

  create_table "orders", force: :cascade do |t|
    t.references "account", null: false, foreign_key: true
    t.integer "quantity", null: false
    t.integer "total_cents", default: 0, null: false
    t.string "note"
    t.boolean "receipt_sent", default: false, null: false
    t.timestamps
  end
end
