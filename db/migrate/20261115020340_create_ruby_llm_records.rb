class CreateRubyLlmRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :ruby_llm_models, id: :bigint do |t|
      t.string :model_id, null: false
      t.string :name, null: false
      t.string :provider, null: false
      t.string :family
      t.datetime :model_created_at
      t.integer :context_window
      t.integer :max_output_tokens
      t.date :knowledge_cutoff
      t.datetime :unlisted_at

      t.jsonb :modalities, default: {}
      t.jsonb :capabilities, default: []
      t.jsonb :pricing, default: {}
      t.jsonb :metadata, default: {}

      t.timestamps

      t.index [ :provider, :model_id ], unique: true
      t.index :provider
      t.index :family
      t.index :capabilities, using: :gin
      t.index :modalities, using: :gin
    end

    create_table :ruby_llm_tool_calls, id: :bigint do |t|
      t.references :message, polymorphic: true, null: false, type: :bigint, index: false
      t.references :result, polymorphic: true, type: :bigint, index: false
      t.string :tool_call_id, null: false
      t.string :provider_call_id
      t.string :namespace
      t.string :name, null: false
      t.text :thought_signature
      t.string :approval
      t.boolean :remote, default: false, null: false
      t.datetime :claimed_until

      t.jsonb :arguments, default: {}
      t.jsonb :mcp_state
      t.jsonb :mcp_result

      t.timestamps

      t.index [ :message_type, :message_id ]
      t.index [ :result_type, :result_id ]
      t.index :tool_call_id, unique: true
      t.index :name
    end

    create_table :ruby_llm_mcp_credentials, id: :bigint do |t|
      t.references :owner, polymorphic: true, type: :bigint
      t.string :key, null: false
      t.text :data
      t.timestamps

      t.index :key, unique: true
    end

    create_table :ruby_llm_usages, id: :bigint do |t|
      t.references :chat, polymorphic: true, type: :bigint, index: false
      t.references :message, polymorphic: true, type: :bigint, index: false
      t.references :owner, polymorphic: true, type: :bigint, index: false
      t.string :operation, null: false
      t.string :provider, null: false
      t.string :model, null: false
      t.string :status, null: false
      t.integer :input_tokens
      t.integer :output_tokens
      t.integer :cache_read_tokens
      t.integer :cache_write_tokens
      t.integer :thinking_tokens
      t.integer :characters
      t.decimal :audio_seconds, precision: 16, scale: 6
      t.integer :search_units

      t.jsonb :server_tool_use

      t.decimal :input_cost, precision: 16, scale: 10
      t.decimal :output_cost, precision: 16, scale: 10
      t.decimal :cache_read_cost, precision: 16, scale: 10
      t.decimal :cache_write_cost, precision: 16, scale: 10
      t.decimal :thinking_cost, precision: 16, scale: 10
      t.decimal :characters_cost, precision: 16, scale: 10
      t.decimal :audio_seconds_cost, precision: 16, scale: 10
      t.decimal :search_units_cost, precision: 16, scale: 10
      t.decimal :total_cost, precision: 16, scale: 10
      t.string :workflow_id
      t.string :workflow_name
      t.string :workflow_step_id
      t.string :workflow_step_name
      t.timestamps

      t.index [ :chat_type, :chat_id ]
      t.index [ :message_type, :message_id ]
      t.index [ :owner_type, :owner_id ]
      t.index :status
      t.index :workflow_id
      t.check_constraint "operation::text IN ('chat', 'embedding', 'moderation', 'image', 'speech', 'transcription', 'ocr', 'rerank', 'judgment', 'video', 'research', 'code_execution')"
      t.check_constraint "status::text IN ('pending', 'succeeded', 'failed', 'cancelled')"
    end

    create_table :ruby_llm_queued_messages, id: :bigint do |t|
      t.references :chat, polymorphic: true, null: false, type: :bigint, index: false
      t.references :sender, polymorphic: true, type: :bigint, index: false
      t.text :content
      t.boolean :steer, default: true, null: false
      t.timestamps

      t.index [ :chat_type, :chat_id ]
      t.index [ :sender_type, :sender_id ]
    end

    create_table :ruby_llm_chat_files, id: :bigint do |t|
      t.references :chat, polymorphic: true, null: false, type: :bigint, index: false
      t.references :owner, polymorphic: true, type: :bigint, index: false
      t.string :path, null: false
      t.string :content_type
      t.bigint :byte_size
      t.string :digest
      t.text :text
      t.string :read_digest
      t.timestamps

      t.index [ :chat_type, :chat_id, :path ]
      t.index [ :owner_type, :owner_id ]
    end

    create_table :ruby_llm_batches, id: :bigint do |t|
      t.string :provider_batch_id, null: false
      t.string :provider, null: false
      t.string :status, null: false
      t.string :raw_status
      t.boolean :completed, null: false, default: false
      t.string :chat_type
      t.string :batch_protocol

      t.jsonb :chat_ids, default: []
      t.jsonb :request_counts
      t.jsonb :reported_cost

      t.timestamps

      t.index [ :provider, :provider_batch_id ], unique: true
      t.index :status
    end

    create_table :ruby_llm_provider_files, id: :bigint do |t|
      t.string :blob_key, null: false
      t.string :provider, null: false
      t.string :account, null: false
      t.text :file_id, null: false
      t.datetime :expires_at
      t.timestamps

      t.index [ :blob_key, :provider, :account ], unique: true, name: "index_ruby_llm_provider_files_uniqueness"
    end
  end
end
