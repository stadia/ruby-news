# frozen_string_literal: true

require "test_helper"

class Articles::AgentRunnerTest < ActiveSupport::TestCase
  SiteStub = Struct.new(:client)

  class TagListStub
    attr_reader :added

    def initialize
      @added = []
    end

    def add(*tags)
      @added.concat(tags)
    end
  end

  class ArticleStub
    attr_reader :id, :tag_list, :site, :updated_content
    attr_accessor :discarded

    def initialize(site_client: "rss")
      @id = 123
      @tag_list = TagListStub.new
      @site = SiteStub.new(site_client)
      @discarded = false
    end

    def update!(attrs)
      @updated_content = attrs
    end

    def discard!
      @discarded = true
    end
  end

  # ruby_llm 2.0의 스키마 응답은 content에 JSON 문자열, parsed에 Hash를 담는다.
  # 실제 Message를 써야 content/parsed 계약이 바뀌었을 때 테스트가 잡아낸다.
  def llm_message(payload, finish_reason)
    RubyLLM::Message.new(role: :assistant, content: payload&.to_json, finish_reason:)
  end

  class AgentStub
    def initialize(message)
      @message = message
    end

    def ask(_prompt)
      @message
    end
  end

  test "문자열 tags도 안전하게 처리한다" do
    article = ArticleStub.new
    message = llm_message({ tags: "Ruby", summary_body: "body" }, "stop")

    ArticleAgent.stub(:new, AgentStub.new(message)) do
      result = Articles::AgentRunner.run(article:, prompt: "prompt")

      assert_predicate result, :success?
      assert_equal article, result.value!
    end

    assert_equal [ "ruby" ], article.tag_list.added
    assert_equal({ "summary_body" => "body" }, article.updated_content)
    refute article.discarded
  end

  test "blank 또는 비문자열 tags는 무시하고 유효한 tag만 추가한다" do
    article = ArticleStub.new
    message = llm_message({ tags: [ "Ruby", nil, " ", "Rails", { bad: true } ], summary_body: "body" }, "stop")

    ArticleAgent.stub(:new, AgentStub.new(message)) do
      result = Articles::AgentRunner.run(article:, prompt: "prompt")

      assert_predicate result, :success?
      assert_equal article, result.value!
    end

    assert_equal %w[ruby rails], article.tag_list.added
    assert_equal({ "summary_body" => "body" }, article.updated_content)
    refute article.discarded
  end

  test "escape된 summary_body의 개행/따옴표를 실제 문자로 정규화한다" do
    article = ArticleStub.new
    message = llm_message({ summary_body: '첫 줄\n둘째 줄\t탭 \"인용\"' }, "stop")

    ArticleAgent.stub(:new, AgentStub.new(message)) do
      result = Articles::AgentRunner.run(article:, prompt: "prompt")

      assert_predicate result, :success?
    end

    assert_equal({ "summary_body" => "첫 줄\n둘째 줄\t탭 \"인용\"" }, article.updated_content)
  end

  # 성공 판별을 Article 클래스 검사로 하면 개발 환경 리로딩 시 is_a?(Article)이 false가 되어
  # 정상 결과가 Failure(article)로 뒤집힌다. 그래서 Result 타입으로 성공/실패를 구분한다.
  test "content가 비어 있으면 기사를 discard하고 finish_reason으로 Failure를 반환한다" do
    article = ArticleStub.new
    message = llm_message(nil, "length")

    ArticleAgent.stub(:new, AgentStub.new(message)) do
      result = Articles::AgentRunner.run(article:, prompt: "prompt")

      assert_predicate result, :failure?
      assert_equal :length, result.failure
    end

    assert article.discarded
    assert_nil article.updated_content
  end
end
