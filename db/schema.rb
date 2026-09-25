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

ActiveRecord::Schema[8.1].define(version: 2026_09_25_000000) do
  create_schema "ra_news", if_not_exists: true

  # These are extensions that must be enabled in order to support this database
  enable_extension "fuzzystrmatch"
  enable_extension "pg_bigm"
  enable_extension "pg_catalog.plpgsql"
  enable_extension "textsearch_ko"
  enable_extension "vector"

  create_table "ra_news.active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "ra_news.active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "ra_news.active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "ra_news.articles", force: :cascade do |t|
    t.text "body", comment: "The main content of the article"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.halfvec "embedding", limit: 3072
    t.bigint "fedipub_actor_id"
    t.string "federated_url"
    t.string "host"
    t.boolean "is_posted", default: false, comment: "소셜에 게시되었는지 여부를 나타냅니다."
    t.boolean "is_related", default: false, null: false
    t.boolean "is_youtube", default: false, null: false
    t.integer "likers_count", default: 0, null: false
    t.string "origin_url", default: "", null: false
    t.integer "posts_count", default: 0, null: false
    t.datetime "published_at"
    t.bigint "site_id"
    t.string "slug"
    t.jsonb "social_post_ids", default: {}
    t.text "summary_body", comment: "원문 상세 요약"
    t.jsonb "summary_detail"
    t.jsonb "summary_key"
    t.string "title", limit: 200
    t.string "title_ko", limit: 200
    t.datetime "updated_at", null: false
    t.string "url"
    t.bigint "user_id"
    t.string "title_ja", limit: 200
    t.jsonb "summary_key_ja"
    t.jsonb "summary_detail_ja"
    t.text "summary_body_ja"
    t.integer "boosters_count", default: 0, null: false
    t.index ["created_at"], name: "index_articles_on_created_at"
    t.index ["deleted_at", "published_at", "created_at"], name: "index_articles_on_deleted_at_and_published_at_and_created_at", where: "(deleted_at IS NULL)"
    t.index ["deleted_at", "slug", "title_ko", "id"], name: "index_articles_on_deleted_at_and_slug_and_title_ko_and_id", where: "((deleted_at IS NULL) AND (slug IS NOT NULL) AND (title_ko IS NOT NULL))", comment: "Optimized for listing articles with slug and title"
    t.index ["embedding"], name: "index_articles_on_embedding", opclass: :halfvec_cosine_ops, using: :hnsw
    t.index ["fedipub_actor_id"], name: "index_articles_on_fedipub_actor_id"
    t.index ["is_related", "published_at"], name: "index_articles_on_is_related_and_published_at"
    t.index ["origin_url"], name: "index_articles_on_origin_url", unique: true
    t.index ["published_at"], name: "index_articles_on_published_at"
    t.index ["site_id", "published_at"], name: "index_articles_on_site_id_and_published_at"
    t.index ["site_id"], name: "index_articles_on_site_id"
    t.index ["slug"], name: "index_articles_on_slug", unique: true, where: "(deleted_at IS NULL)"
    t.index ["url"], name: "index_articles_on_url", unique: true
    t.index ["user_id"], name: "index_articles_on_user_id"
  end

  create_table "ra_news.boosts", force: :cascade do |t|
    t.bigint "actor_id", null: false
    t.string "boostable_type", null: false
    t.bigint "boostable_id", null: false
    t.datetime "created_at", null: false
    t.index ["actor_id", "boostable_type", "boostable_id"], name: "index_boosts_on_actor_and_boostable", unique: true
    t.index ["boostable_type", "boostable_id"], name: "index_boosts_on_boostable"
  end

  create_table "ra_news.fedipub_activities", force: :cascade do |t|
    t.string "action", null: false
    t.bigint "actor_id", null: false
    t.string "audience"
    t.string "bcc"
    t.string "bto"
    t.string "cc"
    t.datetime "created_at", null: false
    t.bigint "entity_id", null: false
    t.string "entity_type", null: false
    t.string "federated_url"
    t.string "to"
    t.datetime "updated_at", null: false
    t.string "uuid"
    t.string "result"
    t.string "instrument"
    t.index ["actor_id"], name: "index_fedipub_activities_on_actor_id"
    t.index ["entity_type", "entity_id"], name: "index_fedipub_activities_on_entity"
    t.index ["federated_url"], name: "index_fedipub_activities_on_federated_url", unique: true
    t.index ["uuid"], name: "index_fedipub_activities_on_uuid", unique: true
  end

  create_table "ra_news.fedipub_actors", force: :cascade do |t|
    t.string "actor_type"
    t.datetime "created_at", null: false
    t.integer "entity_id"
    t.string "entity_type"
    t.json "extensions"
    t.string "federated_url"
    t.string "followers_url"
    t.string "followings_url"
    t.string "inbox_url"
    t.integer "likees_count", default: 0, null: false
    t.boolean "local", default: false, null: false
    t.string "name"
    t.string "outbox_url"
    t.text "private_key"
    t.string "profile_url"
    t.text "public_key"
    t.string "server"
    t.datetime "tombstoned_at"
    t.datetime "updated_at", null: false
    t.string "username"
    t.string "uuid"
    t.string "shared_inbox_url"
    t.integer "boostees_count", default: 0, null: false
    t.index ["entity_type", "entity_id"], name: "index_fedipub_actors_on_entity", unique: true
    t.index ["federated_url"], name: "index_fedipub_actors_on_federated_url", unique: true
    t.index ["uuid"], name: "index_fedipub_actors_on_uuid", unique: true
  end

  create_table "ra_news.fedipub_blocks", force: :cascade do |t|
    t.bigint "actor_id", null: false
    t.datetime "created_at", null: false
    t.bigint "target_actor_id", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id", "target_actor_id"], name: "index_fedipub_blocks_on_actor_id_and_target_actor_id", unique: true
    t.index ["actor_id"], name: "index_fedipub_blocks_on_actor_id"
    t.index ["target_actor_id"], name: "index_fedipub_blocks_on_target_actor_id"
  end

  create_table "ra_news.fedipub_featured_items", force: :cascade do |t|
    t.bigint "actor_id", null: false
    t.string "federated_url", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id", "federated_url"], name: "index_fedipub_featured_items_on_actor_id_and_federated_url", unique: true
    t.index ["actor_id"], name: "index_fedipub_featured_items_on_actor_id"
  end

  create_table "ra_news.fedipub_featured_tags", force: :cascade do |t|
    t.bigint "actor_id", null: false
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id", "name"], name: "index_fedipub_featured_tags_on_actor_id_and_name", unique: true
    t.index ["actor_id"], name: "index_fedipub_featured_tags_on_actor_id"
  end

  create_table "ra_news.fedipub_followings", force: :cascade do |t|
    t.bigint "actor_id", null: false
    t.datetime "created_at", null: false
    t.string "federated_url"
    t.integer "status", default: 0
    t.bigint "target_actor_id", null: false
    t.datetime "updated_at", null: false
    t.string "uuid"
    t.index ["actor_id", "target_actor_id"], name: "index_fedipub_followings_on_actor_id_and_target_actor_id", unique: true
    t.index ["actor_id"], name: "index_fedipub_followings_on_actor_id"
    t.index ["target_actor_id"], name: "index_fedipub_followings_on_target_actor_id"
    t.index ["uuid"], name: "index_fedipub_followings_on_uuid", unique: true
  end

  create_table "ra_news.fedipub_hosts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "domain", null: false
    t.string "nodeinfo_url"
    t.text "protocols", default: "[]"
    t.text "services", default: "{}"
    t.string "software_name"
    t.string "software_version"
    t.datetime "updated_at", null: false
    t.index ["domain"], name: "index_fedipub_hosts_on_domain", unique: true
  end

  create_table "ra_news.friendly_id_slugs", force: :cascade do |t|
    t.datetime "created_at"
    t.string "scope"
    t.string "slug", null: false
    t.integer "sluggable_id", null: false
    t.string "sluggable_type", limit: 50
    t.index ["slug", "sluggable_type", "scope"], name: "index_friendly_id_slugs_on_slug_and_sluggable_type_and_scope", unique: true
    t.index ["slug", "sluggable_type"], name: "index_friendly_id_slugs_on_slug_and_sluggable_type"
    t.index ["sluggable_type", "sluggable_id"], name: "index_friendly_id_slugs_on_sluggable_type_and_sluggable_id"
  end

  create_table "ra_news.jwt_denylists", force: :cascade do |t|
    t.string "jti", null: false
    t.datetime "exp", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["jti"], name: "index_jwt_denylists_on_jti", unique: true
  end

  create_table "ra_news.likes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "likeable_id", null: false
    t.string "likeable_type", null: false
    t.bigint "actor_id", null: false
    t.index ["actor_id", "likeable_type", "likeable_id"], name: "index_likes_on_actor_and_likeable", unique: true
    t.index ["likeable_type", "likeable_id"], name: "index_likes_on_likeable"
  end

  create_table "ra_news.notification_channels", force: :cascade do |t|
    t.string "type", null: false
    t.string "status", default: "active", null: false
    t.datetime "last_verified_at"
    t.string "remote_id", null: false
    t.string "name", null: false
    t.string "webhook_url", null: false
    t.string "channel_id", null: false
    t.string "channel_name", null: false
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "deleted_at"
    t.index ["deleted_at"], name: "index_notification_channels_on_deleted_at"
    t.index ["type", "remote_id"], name: "index_notification_channels_on_type_and_remote_id", unique: true
  end

  create_table "ra_news.notification_deliveries", force: :cascade do |t|
    t.string "type", null: false
    t.bigint "article_id", null: false
    t.bigint "notification_channel_id", null: false
    t.string "channel_id", null: false
    t.string "channel_name", null: false
    t.string "status", default: "failed", null: false
    t.datetime "sent_at"
    t.text "error_message"
    t.string "message_id"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["article_id", "notification_channel_id", "channel_id"], name: "idx_notification_deliveries_uniqueness", unique: true
    t.index ["notification_channel_id"], name: "index_notification_deliveries_on_notification_channel_id"
  end

  create_table "ra_news.oauth_accounts", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "provider", null: false
    t.string "uid", null: false
    t.string "email"
    t.boolean "email_verified", default: false, null: false
    t.jsonb "raw_info", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["provider", "uid"], name: "index_oauth_accounts_on_provider_and_uid", unique: true
    t.index ["user_id", "provider"], name: "index_oauth_accounts_on_user_id_and_provider", unique: true
    t.check_constraint "provider::text = ANY (ARRAY['google_oauth2'::text, 'apple'::text, 'github'::text])", name: "oauth_accounts_provider_allowed"
  end

  create_table "ra_news.pg_search_documents", force: :cascade do |t|
    t.text "content"
    t.datetime "created_at", null: false
    t.bigint "searchable_id"
    t.string "searchable_type"
    t.tsvector "tsvector_content_tsearch"
    t.datetime "updated_at", null: false
    t.index ["content"], name: "index_pg_search_documents_on_content_bigm", opclass: :gin_bigm_ops, using: :gin
    t.index ["searchable_type", "searchable_id", "created_at"], name: "idx_on_searchable_type_searchable_id_created_at_0108fa1d12"
    t.index ["searchable_type", "searchable_id"], name: "index_pg_search_documents_on_searchable"
    t.index ["tsvector_content_tsearch"], name: "index_pg_search_documents_on_tsvector_content_tsearch", using: :gin
  end

  create_table "ra_news.posts", force: :cascade do |t|
    t.bigint "article_id"
    t.text "body", null: false
    t.integer "children_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.integer "depth", default: 0, null: false
    t.bigint "fedipub_actor_id"
    t.string "federated_url"
    t.integer "lft", null: false
    t.integer "likers_count", default: 0, null: false
    t.jsonb "media_attachments", default: [], null: false
    t.bigint "parent_id"
    t.integer "rgt", null: false
    t.string "title", limit: 255
    t.datetime "updated_at", null: false
    t.string "url", limit: 255
    t.bigint "user_id"
    t.string "slug", limit: 22
    t.integer "boosters_count", default: 0, null: false
    t.integer "post_type", default: 0, null: false
    t.integer "status", default: 1, null: false
    t.datetime "published_at"
    t.datetime "deleted_at"
    t.index ["article_id"], name: "index_posts_on_article_id"
    t.index ["deleted_at"], name: "index_posts_on_deleted_at"
    t.index ["federated_url"], name: "index_posts_on_federated_url", unique: true
    t.index ["fedipub_actor_id"], name: "index_posts_on_fedipub_actor_id"
    t.index ["lft"], name: "index_posts_on_lft"
    t.index ["parent_id", "created_at"], name: "index_posts_on_parent_id_and_created_at"
    t.index ["post_type", "status", "created_at"], name: "index_posts_on_type_status_created_at"
    t.index ["rgt"], name: "index_posts_on_rgt"
    t.index ["slug"], name: "index_posts_on_slug", unique: true
    t.index ["user_id", "post_type", "status", "created_at"], name: "index_posts_on_user_type_status_created_at"
    t.index ["user_id"], name: "index_posts_on_user_id"
  end

  create_table "ra_news.preferences", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.jsonb "value", default: {}
    t.index ["name"], name: "index_preferences_on_name", unique: true
  end

  create_table "ra_news.push_subscriptions", force: :cascade do |t|
    t.string "auth", null: false
    t.datetime "created_at", null: false
    t.text "endpoint", null: false
    t.datetime "expiration_time"
    t.datetime "last_error_at"
    t.datetime "last_sent_at"
    t.string "p256dh", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["endpoint"], name: "index_push_subscriptions_on_endpoint", unique: true
    t.index ["user_id"], name: "index_push_subscriptions_on_user_id"
  end

  create_table "ra_news.refresh_tokens", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "token_digest", null: false
    t.datetime "expires_at", null: false
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["token_digest"], name: "index_refresh_tokens_on_token_digest", unique: true
    t.index ["user_id"], name: "index_refresh_tokens_on_user_id"
  end

  create_table "ra_news.roles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_roles_on_name", unique: true
  end

  create_table "ra_news.sites", force: :cascade do |t|
    t.string "base_uri"
    t.string "channel"
    t.integer "client", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "email"
    t.datetime "last_checked_at"
    t.string "name", null: false
    t.string "path"
    t.datetime "updated_at", null: false
    t.string "url"
    t.index ["client", "id"], name: "index_sites_on_client_and_id"
    t.index ["deleted_at"], name: "index_sites_on_deleted_at"
    t.index ["url"], name: "index_sites_unique_url_for_rss", unique: true, where: "((client = 0) AND (deleted_at IS NULL))"
  end

  create_table "ra_news.taggings", force: :cascade do |t|
    t.string "context", limit: 128
    t.datetime "created_at", precision: nil
    t.bigint "tag_id"
    t.bigint "taggable_id"
    t.string "taggable_type"
    t.bigint "tagger_id"
    t.string "tagger_type"
    t.string "tenant", limit: 128
    t.index ["tag_id", "taggable_id", "taggable_type", "context", "tagger_id", "tagger_type"], name: "taggings_idx", unique: true
    t.index ["tag_id"], name: "index_taggings_on_tag_id"
    t.index ["taggable_id", "taggable_type", "context", "tag_id"], name: "index_taggings_on_taggable_and_context_and_tag_id"
    t.index ["taggable_id", "taggable_type", "context"], name: "taggings_taggable_context_idx"
    t.index ["taggable_id", "taggable_type", "tagger_id", "context"], name: "taggings_idy"
    t.index ["taggable_id"], name: "index_taggings_on_taggable_id"
    t.index ["taggable_type", "taggable_id"], name: "index_taggings_on_taggable_type_and_taggable_id"
    t.index ["taggable_type"], name: "index_taggings_on_taggable_type"
    t.index ["tagger_id", "tagger_type"], name: "index_taggings_on_tagger_id_and_tagger_type"
    t.index ["tagger_id"], name: "index_taggings_on_tagger_id"
    t.index ["tenant"], name: "index_taggings_on_tenant"
  end

  create_table "ra_news.tags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "is_confirmed", default: false, null: false
    t.string "name"
    t.integer "taggings_count", default: 0
    t.datetime "updated_at", null: false
    t.index "lower((name)::text)", name: "index_tags_on_lower_name"
    t.index ["name"], name: "index_tags_on_name", unique: true
  end

  create_table "ra_news.users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "encrypted_password", null: false
    t.integer "likees_count", default: 0, null: false
    t.string "name", default: "", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.string "roles", default: ["user"], array: true
    t.datetime "updated_at", null: false
    t.string "username", limit: 30
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "confirmation_sent_at"
    t.string "unconfirmed_email"
    t.string "locale", limit: 2
    t.string "signup_host", limit: 20
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["username"], name: "index_users_on_username", unique: true
  end

  add_foreign_key "ra_news.active_storage_attachments", "ra_news.active_storage_blobs", column: "blob_id"
  add_foreign_key "ra_news.active_storage_variant_records", "ra_news.active_storage_blobs", column: "blob_id"
  add_foreign_key "ra_news.articles", "ra_news.fedipub_actors", on_delete: :nullify
  add_foreign_key "ra_news.articles", "ra_news.sites", on_delete: :nullify
  add_foreign_key "ra_news.articles", "ra_news.users", on_delete: :nullify
  add_foreign_key "ra_news.boosts", "ra_news.fedipub_actors", column: "actor_id"
  add_foreign_key "ra_news.fedipub_activities", "ra_news.fedipub_actors", column: "actor_id"
  add_foreign_key "ra_news.fedipub_blocks", "ra_news.fedipub_actors", column: "actor_id"
  add_foreign_key "ra_news.fedipub_blocks", "ra_news.fedipub_actors", column: "target_actor_id"
  add_foreign_key "ra_news.fedipub_followings", "ra_news.fedipub_actors", column: "actor_id"
  add_foreign_key "ra_news.fedipub_followings", "ra_news.fedipub_actors", column: "target_actor_id"
  add_foreign_key "ra_news.likes", "ra_news.fedipub_actors", column: "actor_id"
  add_foreign_key "ra_news.notification_deliveries", "ra_news.articles"
  add_foreign_key "ra_news.notification_deliveries", "ra_news.notification_channels"
  add_foreign_key "ra_news.oauth_accounts", "ra_news.users"
  add_foreign_key "ra_news.posts", "ra_news.articles"
  add_foreign_key "ra_news.posts", "ra_news.fedipub_actors", on_delete: :nullify
  add_foreign_key "ra_news.posts", "ra_news.posts", column: "parent_id", on_delete: :nullify
  add_foreign_key "ra_news.posts", "ra_news.users", on_delete: :nullify
  add_foreign_key "ra_news.push_subscriptions", "ra_news.users"
  add_foreign_key "ra_news.refresh_tokens", "ra_news.users"
  add_foreign_key "ra_news.taggings", "ra_news.tags"

end
