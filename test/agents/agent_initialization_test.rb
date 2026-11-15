# frozen_string_literal: true

require "test_helper"

class AgentInitializationTest < ActiveSupport::TestCase
  setup do
    @context = RubyLLM.context do |config|
      config.openai_api_key = "test-key"
      config.ollama_cloud_api_key = "test-key"
    end
  end

  # 생성자를 stub하면 에이전트 설정(skills 등) 적용 단계의 실패를 잡지 못한다.
  [ ArticleAgent, ArticleJapaneseAgent ].each do |agent_class|
    test "#{agent_class}는 skills 선언 없이 초기화된다" do
      chat = agent_class.new(context: @context).chat

      assert_instance_of RubyLLM::Chat, chat
      assert_includes chat.tools.keys, :search_related_articles
    end
  end

  test "윤문 에이전트는 한국어 윤문 스킬을 로드한다" do
    chat = HumanMonolithAgent.new(context: @context).chat

    assert_equal [ "humanize-korean" ], chat.skills.map(&:name)
  end

  test "윤문 에이전트는 스킬 스크립트를 샌드박스에서 실행할 수 있다" do
    chat = HumanMonolithAgent.new(context: @context).chat

    assert_equal SkillScriptSandbox, chat.tools.fetch(:run_code).sandbox.policy
  end

  test "윤문 에이전트 응답 스키마는 게이트 미검증 여부를 받는다" do
    chat = HumanMonolithAgent.new(context: @context).chat

    assert_includes chat.schema.to_json, "gate_unverified"
  end

  # RubyLLM에는 Agent 도구가 없어, 스킬이 부르는 하위 에이전트 지침을 load_skill로 읽어 직접 수행한다.
  test "윤문 에이전트는 스킬의 하위 에이전트 지침을 읽을 수 있다" do
    loader = HumanMonolithAgent.new(context: @context).chat.tools.fetch(:load_skill)

    %w[humanize-diagnostician humanize-monolith humanize-finalizer].each do |name|
      assert_includes loader.execute(skill: "humanize-korean", file: "references/agents/#{name}.md").to_s, "name: #{name}"
    end
  end

  # 파일 저장소가 없으면 run_code 실행마다 작업 디렉터리가 지워져, shim이 만든
  # _workspace를 다음 실행(진단 결합·게이트)이 찾지 못한다.
  test "윤문 에이전트는 실행 사이에 작업 파일을 유지할 파일 저장소를 쓴다" do
    chat = HumanMonolithAgent.new(context: @context).chat

    assert_instance_of RubyLLM::FileStore::Memory, chat.file_store
    assert chat.tools.fetch(:run_code).parameters_schema.dig("properties", "files")
  end
end
