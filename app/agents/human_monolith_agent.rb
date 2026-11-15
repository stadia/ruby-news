# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

class HumanMonolithAgent < RubyLLM::Agent
  # model "qwen/qwen3.7-plus", provider: :openrouter, assume_model_exists: true
  model "deepseek-v4.1-flash", provider: :ollama_cloud
  temperature 0.2
  skills :humanize_korean
  code_execution
  # run_code 실행마다 작업 디렉터리가 지워지므로, shim이 만든 _workspace를 다음 실행에서
  # files:로 다시 받도록 채팅별 저장소를 둔다. 도구 결과는 이전처럼 잘라 내지 않는다
  # (전역 config.context_budget 상한은 별도로 적용된다).
  file_store :memory, inline_limit: false

  schema do
    array :summary_key, of: :string, description: "윤문된 핵심 요약 배열 (원본 길이·항목 수 유지)"

    object :summary_detail, description: "윤문된 상세 요약" do
      string :introduction, description: "윤문된 introduction (200-300자)"
      string :conclusion, description: "윤문된 conclusion (200-300자)"
    end

    string :summary_body, description: "윤문된 마크다운 본론 (헤딩·구조·링크 보존)"

    object :metrics, description: "윤문 메트릭" do
      integer :original_chars, description: "원본 총 글자수 (key+detail+body)"
      integer :rewritten_chars, description: "윤문 총 글자수"
      number :change_rate, description: "변경률 (0.0~1.0)"
      string :grade, description: "등급: A/B/C/D"
    end

    boolean :over_polish_aborted, description: "변경률 50% 초과로 롤백되었는지 여부"
    boolean :gate_unverified, description: "정량 shim 또는 구조 게이트(verify_gates.rb)를 실행하지 못해 윤문을 검증하지 못했는지 여부"
  end
end
