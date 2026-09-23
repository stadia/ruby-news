# ruby_llm 2.0 업그레이드에 앞서 ruby_llm-monitoring 젬을 제거했다. 0.4.0은 2.0의
# 계측 payload(tokens/cost 객체)를 읽지 못해 비용·토큰이 비어 기록되므로 이벤트 테이블도 정리한다.
class DropRubyLlmMonitoringEvents < ActiveRecord::Migration[8.1]
  def up
    drop_table :ruby_llm_monitoring_events, if_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
