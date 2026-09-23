# This migration comes from ruby_llm_monitoring (originally 20260223214109)
class AddThinkingTokensToRubyLlmMonitoringEvents < ActiveRecord::Migration[7.2]
  # 20260726005859와 같은 이유로 젬 헬퍼 대신 PostgreSQL 식을 직접 쓴다.
  def change
    add_column :ruby_llm_monitoring_events, :thinking_tokens, :virtual, type: :integer, as: "(payload->>'thinking_tokens')::integer", stored: true
  end
end
