# frozen_string_literal: true

require "test_helper"

class AgentInitializationTest < ActiveSupport::TestCase
  setup do
    @context = RubyLLM.context do |config|
      config.openrouter_api_key = "test-key"
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
end
