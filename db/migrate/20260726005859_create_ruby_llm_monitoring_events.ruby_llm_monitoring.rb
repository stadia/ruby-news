# This migration comes from ruby_llm_monitoring (originally 20251208171258)
class CreateRubyLlmMonitoringEvents < ActiveRecord::Migration[7.2]
  # ruby_llm-monitoring 젬을 제거한 뒤에도 새 환경에서 db:migrate가 돌도록
  # 젬의 MigrationHelpers가 PostgreSQL에서 만들던 식을 그대로 옮겨 적었다.
  def change
    create_table :ruby_llm_monitoring_events do |t|
      t.integer :allocations
      t.float :cost
      t.float :cpu_time
      t.float :duration
      t.float :end
      t.float :gc_time
      t.float :idle_time
      t.string :name
      t.json :payload
      t.float :time
      t.string :transaction_id

      t.virtual :provider, type: :string, as: "payload->>'provider'", stored: true
      t.virtual :model, type: :string, as: "payload->>'model'", stored: true
      t.virtual :input_tokens, type: :integer, as: "(payload->>'input_tokens')::integer", stored: true
      t.virtual :output_tokens, type: :integer, as: "(payload->>'output_tokens')::integer", stored: true
      t.virtual :exception_class, type: :string, as: "(payload->'exception'->>0)", stored: true
      t.virtual :exception_message, type: :string, as: "(payload->'exception'->>1)", stored: true

      t.timestamps
    end
  end
end
