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

ActiveRecord::Schema[8.1].define(version: 2026_01_03_012855) do
  create_table "accounts", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "aws_access_key_id"
    t.string "aws_region", default: "us-east-1"
    t.string "aws_secret_access_key"
    t.string "brand_logo"
    t.datetime "created_at", null: false
    t.string "default_from_email"
    t.string "default_reply_to_email"
    t.string "name", null: false
    t.datetime "paused_at"
    t.integer "plan", default: 0, null: false
    t.string "ses_configuration_set_name"
    t.integer "ses_max_24_hour_send", default: 200
    t.integer "ses_max_send_rate", default: 1
    t.datetime "ses_quota_reset_at"
    t.integer "ses_sent_last_24_hours", default: 0
    t.integer "setup_step", default: 0, null: false
    t.string "subdomain", null: false
    t.string "tracking_domain"
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_accounts_on_active"
    t.index ["subdomain"], name: "index_accounts_on_subdomain", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "api_keys", force: :cascade do |t|
    t.integer "account_id", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.string "last_4", null: false
    t.datetime "last_used_at"
    t.string "name", null: false
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["account_id", "active"], name: "index_api_keys_on_account_id_and_active"
    t.index ["account_id"], name: "index_api_keys_on_account_id"
    t.index ["token_digest"], name: "index_api_keys_on_token_digest", unique: true
    t.index ["user_id"], name: "index_api_keys_on_user_id"
  end

  create_table "campaign_clicks", force: :cascade do |t|
    t.integer "campaign_link_id", null: false
    t.integer "campaign_send_id", null: false
    t.datetime "clicked_at", null: false
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.index ["campaign_link_id"], name: "index_campaign_clicks_on_campaign_link_id"
    t.index ["campaign_send_id", "campaign_link_id"], name: "index_campaign_clicks_on_campaign_send_id_and_campaign_link_id"
    t.index ["campaign_send_id"], name: "index_campaign_clicks_on_campaign_send_id"
  end

  create_table "campaign_links", force: :cascade do |t|
    t.integer "campaign_id", null: false
    t.integer "click_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "original_url", null: false
    t.string "token", null: false
    t.integer "unique_click_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_id", "token"], name: "index_campaign_links_on_campaign_id_and_token", unique: true
    t.index ["campaign_id"], name: "index_campaign_links_on_campaign_id"
  end

  create_table "campaign_sends", force: :cascade do |t|
    t.text "bounce_reason"
    t.string "bounce_type"
    t.datetime "bounced_at"
    t.integer "campaign_id", null: false
    t.integer "click_count", default: 0, null: false
    t.datetime "complained_at"
    t.datetime "created_at", null: false
    t.datetime "delivered_at"
    t.datetime "first_clicked_at"
    t.datetime "next_retry_at"
    t.integer "open_count", default: 0, null: false
    t.datetime "opened_at"
    t.integer "retry_count", default: 0, null: false
    t.datetime "sent_at"
    t.string "ses_message_id"
    t.string "status", default: "pending", null: false
    t.integer "subscriber_id", null: false
    t.datetime "unsubscribed_at"
    t.datetime "updated_at", null: false
    t.index ["campaign_id", "status"], name: "index_campaign_sends_on_campaign_id_and_status"
    t.index ["campaign_id", "subscriber_id"], name: "index_campaign_sends_on_campaign_id_and_subscriber_id", unique: true
    t.index ["campaign_id"], name: "index_campaign_sends_on_campaign_id"
    t.index ["ses_message_id"], name: "index_campaign_sends_on_ses_message_id"
    t.index ["status", "next_retry_at"], name: "index_campaign_sends_on_status_and_next_retry_at"
    t.index ["subscriber_id"], name: "index_campaign_sends_on_subscriber_id"
  end

  create_table "campaigns", force: :cascade do |t|
    t.integer "account_id", null: false
    t.text "body_markdown"
    t.integer "bounced_count", default: 0, null: false
    t.text "canary_send_ids"
    t.datetime "canary_started_at"
    t.integer "clicked_count", default: 0, null: false
    t.integer "complained_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.integer "delivered_count", default: 0, null: false
    t.datetime "finished_sending_at"
    t.string "from_email", null: false
    t.string "from_name", null: false
    t.integer "list_id", null: false
    t.string "name", null: false
    t.integer "opened_count", default: 0, null: false
    t.datetime "queued_at"
    t.string "reply_to_email"
    t.datetime "scheduled_at"
    t.integer "segment_id"
    t.integer "sent_count", default: 0, null: false
    t.datetime "started_sending_at"
    t.string "status", default: "draft", null: false
    t.string "subject", null: false
    t.string "suspension_reason"
    t.integer "template_id"
    t.integer "total_recipients", default: 0, null: false
    t.integer "unsubscribed_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "status"], name: "index_campaigns_on_account_id_and_status"
    t.index ["account_id"], name: "index_campaigns_on_account_id"
    t.index ["list_id"], name: "index_campaigns_on_list_id"
    t.index ["scheduled_at"], name: "index_campaigns_on_scheduled_at"
    t.index ["segment_id"], name: "index_campaigns_on_segment_id"
    t.index ["template_id"], name: "index_campaigns_on_template_id"
  end

  create_table "custom_field_definitions", force: :cascade do |t|
    t.integer "account_id", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "field_type", default: "text", null: false
    t.string "name", null: false
    t.boolean "required", default: false, null: false
    t.datetime "updated_at", null: false
    t.json "validation_rules", default: {}
    t.index ["account_id", "name"], name: "index_custom_field_definitions_on_account_id_and_name", unique: true
    t.index ["account_id"], name: "index_custom_field_definitions_on_account_id"
  end

  create_table "images", force: :cascade do |t|
    t.integer "account_id", null: false
    t.datetime "created_at", null: false
    t.string "slug"
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_images_on_account_id"
    t.index ["slug"], name: "index_images_on_slug", unique: true
  end

  create_table "invitations", force: :cascade do |t|
    t.datetime "accepted_at"
    t.integer "account_id", null: false
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.datetime "expires_at", null: false
    t.integer "invited_by_id", null: false
    t.string "role", default: "member", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "email"], name: "index_invitations_on_account_id_and_email"
    t.index ["account_id"], name: "index_invitations_on_account_id"
    t.index ["invited_by_id"], name: "index_invitations_on_invited_by_id"
    t.index ["token"], name: "index_invitations_on_token", unique: true
  end

  create_table "list_subscriptions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "list_id", null: false
    t.string "status", default: "active", null: false
    t.datetime "subscribed_at"
    t.integer "subscriber_id", null: false
    t.datetime "unsubscribed_at"
    t.datetime "updated_at", null: false
    t.index ["list_id", "status"], name: "index_list_subscriptions_on_list_id_and_status"
    t.index ["list_id", "subscriber_id"], name: "index_list_subscriptions_on_list_id_and_subscriber_id", unique: true
    t.index ["list_id"], name: "index_list_subscriptions_on_list_id"
    t.index ["subscriber_id", "list_id"], name: "index_list_subscriptions_on_subscriber_id_and_list_id"
    t.index ["subscriber_id"], name: "index_list_subscriptions_on_subscriber_id"
  end

  create_table "lists", force: :cascade do |t|
    t.integer "account_id", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "double_opt_in", default: false, null: false
    t.boolean "enable_subscription_form", default: true, null: false
    t.string "form_redirect_url"
    t.text "form_success_message"
    t.string "name", null: false
    t.integer "subscribers_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "name"], name: "index_lists_on_account_id_and_name"
    t.index ["account_id"], name: "index_lists_on_account_id"
  end

  create_table "segments", force: :cascade do |t|
    t.integer "account_id", null: false
    t.datetime "count_updated_at"
    t.datetime "created_at", null: false
    t.json "criteria", default: []
    t.text "description"
    t.integer "estimated_subscribers_count", default: 0, null: false
    t.integer "list_id", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "list_id"], name: "index_segments_on_account_id_and_list_id"
    t.index ["account_id"], name: "index_segments_on_account_id"
    t.index ["list_id"], name: "index_segments_on_list_id"
  end

  create_table "subscribers", force: :cascade do |t|
    t.integer "account_id", null: false
    t.datetime "bounced_at"
    t.datetime "complained_at"
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.json "custom_attributes", default: {}
    t.string "email", null: false
    t.string "ip_address"
    t.string "source"
    t.string "status", default: "active", null: false
    t.datetime "unsubscribed_at"
    t.datetime "updated_at", null: false
    t.index ["account_id", "email"], name: "index_subscribers_on_account_id_and_email", unique: true
    t.index ["account_id", "status"], name: "index_subscribers_on_account_id_and_status"
    t.index ["account_id"], name: "index_subscribers_on_account_id"
    t.index ["email"], name: "index_subscribers_on_email"
  end

  create_table "templates", force: :cascade do |t|
    t.integer "account_id", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.text "html_content"
    t.boolean "is_default", default: false, null: false
    t.text "markdown_content"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "name"], name: "index_templates_on_account_id_and_name"
    t.index ["account_id"], name: "index_templates_on_account_id"
  end

  create_table "users", force: :cascade do |t|
    t.integer "account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "current_sign_in_at"
    t.string "current_sign_in_ip"
    t.boolean "daily_summary_enabled", default: true, null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "first_name"
    t.string "last_name"
    t.datetime "last_sign_in_at"
    t.string "last_sign_in_ip"
    t.boolean "notify_campaign_complete", default: true, null: false
    t.boolean "notify_campaign_errors", default: true, null: false
    t.boolean "notify_campaign_start", default: true, null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.string "role", default: "member", null: false
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "email"], name: "index_users_on_account_id_and_email", unique: true
    t.index ["account_id"], name: "index_users_on_account_id"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "webhook_endpoints", force: :cascade do |t|
    t.integer "account_id", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "endpoint_type", null: false
    t.string "sns_topic_arn"
    t.datetime "updated_at", null: false
    t.string "webhook_secret"
    t.index ["account_id", "endpoint_type"], name: "index_webhook_endpoints_on_account_id_and_endpoint_type"
    t.index ["account_id"], name: "index_webhook_endpoints_on_account_id"
  end

  create_table "webhook_events", force: :cascade do |t|
    t.integer "account_id", null: false
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.json "payload"
    t.boolean "processed", default: false, null: false
    t.datetime "processed_at"
    t.datetime "updated_at", null: false
    t.index ["account_id", "processed"], name: "index_webhook_events_on_account_id_and_processed"
    t.index ["account_id"], name: "index_webhook_events_on_account_id"
    t.index ["event_type"], name: "index_webhook_events_on_event_type"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "api_keys", "accounts"
  add_foreign_key "api_keys", "users"
  add_foreign_key "campaign_clicks", "campaign_links"
  add_foreign_key "campaign_clicks", "campaign_sends"
  add_foreign_key "campaign_links", "campaigns"
  add_foreign_key "campaign_sends", "campaigns"
  add_foreign_key "campaign_sends", "subscribers"
  add_foreign_key "campaigns", "accounts"
  add_foreign_key "campaigns", "lists"
  add_foreign_key "campaigns", "segments"
  add_foreign_key "campaigns", "templates"
  add_foreign_key "custom_field_definitions", "accounts"
  add_foreign_key "images", "accounts"
  add_foreign_key "invitations", "accounts"
  add_foreign_key "invitations", "users", column: "invited_by_id"
  add_foreign_key "list_subscriptions", "lists"
  add_foreign_key "list_subscriptions", "subscribers"
  add_foreign_key "lists", "accounts"
  add_foreign_key "segments", "accounts"
  add_foreign_key "segments", "lists"
  add_foreign_key "subscribers", "accounts"
  add_foreign_key "templates", "accounts"
  add_foreign_key "users", "accounts"
  add_foreign_key "webhook_endpoints", "accounts"
  add_foreign_key "webhook_events", "accounts"
end
