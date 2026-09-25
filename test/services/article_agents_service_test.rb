# frozen_string_literal: true

# rbs_inline: enabled

require "test_helper"

class ArticleAgentsServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  # ruby_llm 2.0의 스키마 응답은 content에 JSON 문자열, parsed에 Hash를 담는다.
  # 실제 Message를 써야 content/parsed 계약이 바뀌었을 때 테스트가 잡아낸다.
  def llm_message(payload)
    raw_message(payload.to_json)
  end

  # 모델이 스키마를 어기고 JSON이 아닌 텍스트를 돌려준 경우
  def raw_message(content)
    RubyLLM::Message.new(role: :assistant, content:, finish_reason: "stop")
  end

  # run_humanize는 HumanMonolithAgent.chat.with_skills.ask 체인을 타므로
  # 스텁도 with_skills를 지원해야 실제 호출 경로를 검증한다.
  def build_humanize_chat(response, &capture)
    chat = Object.new
    chat.define_singleton_method(:with_skills) { self }
    chat.define_singleton_method(:ask) do |prompt|
      capture&.call(prompt)
      response
    end
    chat
  end

  test "서비스는 OperationService를 상속한다" do
    service = ArticleAgentsService.new

    assert_kind_of OperationService, service
  end

  test "body가 없으면 ContentService 실패를 반환하고 discard한다" do
    article = articles(:ruby_article)
    article.update!(body: nil)

    content_service = Object.new
    content_service.define_singleton_method(:call) { |_article = nil| Dry::Monads::Failure(:no_content) }

    # Pinned to `nil` by the initial assignment otherwise, which rejects the
    # assignment made inside the block below.
    result = nil #: Dry::Monads::Result?
    ContentService.stub(:new, -> { content_service }) do
      result = ArticleAgentsService.new.call(article)
    end

    assert_predicate result, :failure?
    assert_equal :no_content, result.failure
    assert_predicate article.reload, :discarded?
  end

  test "ContentService가 성공해도 본문이 31자 미만이면 :short_body 실패를 반환하고 discard한다" do
    article = articles(:ruby_article)
    article.update!(body: nil)

    content_service = Object.new
    content_service.define_singleton_method(:call) { |_article = nil| Dry::Monads::Success("짧은 본문") }

    result = nil #: Dry::Monads::Result?
    ContentService.stub(:new, -> { content_service }) do
      result = ArticleAgentsService.new.call(article)
    end

    assert_predicate result, :failure?
    assert_equal :short_body, result.failure
    assert_predicate article.reload, :discarded?
  end

  test "run_humanize는 HumanMonolithAgent의 구조화된 응답으로 summary_* 필드를 갱신한다" do
    article = articles(:ruby_article)
    article.update!(
      summary_key: [ "첫 요점", "둘째 요점" ],
      summary_detail: { "introduction" => "도입 문장", "conclusion" => "마무리 문장" },
      summary_body: "원본 요약"
    )

    humanize_response = llm_message({
      "summary_key" => [ "다듬은 첫 요점", "다듬은 둘째 요점" ],
      "summary_detail" => { "introduction" => "다듬은 도입 문장", "conclusion" => "다듬은 마무리 문장" },
      "summary_body" => "### 공격 개요\n\n운문 결과 본문입니다.",
      "metrics" => { "change_rate" => 0.18, "grade" => "A" },
      "over_polish_aborted" => false
    })

    captured_prompt = nil
    chat = build_humanize_chat(humanize_response) { |prompt| captured_prompt = prompt }

    result = nil
    HumanMonolithAgent.stub(:chat, chat) do
      result = ArticleAgentsService.new.send(:run_humanize, article)
    end

    assert_predicate result, :success?
    assert_includes captured_prompt, "summary_key"
    assert_includes captured_prompt, "도입 문장"
    assert_equal [ "다듬은 첫 요점", "다듬은 둘째 요점" ], article.reload.summary_key
    assert_equal({ "introduction" => "다듬은 도입 문장", "conclusion" => "다듬은 마무리 문장" }, article.summary_detail)
    assert_equal "### 공격 개요\n\n운문 결과 본문입니다.", article.summary_body
  end

  # 에이전트 호출 자체(태그 적용·summary_body 정규화·빈 응답 시 discard)는
  # test/functions/articles/agent_runner_test.rb가 담당한다.

  test "썸네일 단계가 실패해도 일본어 번역 단계까지 진행한다" do
    article = articles(:ruby_article)
    article.update!(
      body: "본문 문장입니다. " * 10,
      summary_key: [], # 썸네일 단계가 :no_summary_key로 실패하는 조건
      title_ko: "테스트 제목",
      summary_body: "요약 본문"
    )

    agent_response = llm_message({ "is_related" => true })
    agent = Object.new
    agent.define_singleton_method(:ask) { |_| agent_response }

    humanize_chat = build_humanize_chat(llm_message({}))

    japanese_called = false
    japanese_service = ArticleJapaneseService.new
    japanese_service.define_singleton_method(:japanese_translation) do |_article|
      japanese_called = true
      { title_ja: "テスト", summary_body_ja: "要約" }
    end
    service = ArticleAgentsService.new

    embed_result = Struct.new(:vectors).new(Array.new(3072, 0.0))

    # Pinned to `nil` by the initial assignment otherwise, which rejects the
    # assignment made inside the block below.
    result = nil #: Dry::Monads::Result?
    RubyLLM.stub(:embed, ->(*, **) { embed_result }) do
      ArticleAgent.stub(:new, agent) do
        HumanMonolithAgent.stub(:chat, humanize_chat) do
          ArticleJapaneseService.stub(:new, -> { japanese_service }) do
            result = service.call(article)
          end
        end
      end
    end

    assert japanese_called, "썸네일 실패가 파이프라인을 중단시켜 일본어 번역이 호출되지 않았다"
    assert_predicate result, :success?
    assert_equal "テスト", article.reload.title_ja
  end

  test "discard_unrelated는 자동 수집 기사이면서 is_related=false이면 discard한다" do
    article = articles(:ruby_article) # site.client == "rss"
    article.update!(is_related: false)

    result = ArticleAgentsService.new.send(:discard_unrelated, article)

    assert_predicate result, :success?
    assert_predicate article.reload, :discarded?
  end

  test "discard_unrelated는 is_related=true이거나 자동 정리 대상 수집원이 아니면 유지한다" do
    related = articles(:ruby_article)
    manual = articles(:youtube_ruby_talk) # site.client == "youtube"
    manual.update!(is_related: false)

    service = ArticleAgentsService.new

    assert_predicate service.send(:discard_unrelated, related), :success?
    refute_predicate related.reload, :discarded?

    assert_predicate service.send(:discard_unrelated, manual), :success?
    refute_predicate manual.reload, :discarded?
  end

  test "run_thumbnail은 정리 예정인 무관 기사에 썸네일을 만들지 않는다" do
    article = articles(:ruby_article)
    article.update!(is_related: false, summary_key: [ "요점" ])

    result = nil
    assert_no_enqueued_jobs(only: ArticleThumbnailJob) do
      result = ArticleAgentsService.new.send(:run_thumbnail, article)
    end

    assert_predicate result, :failure?
    assert_equal :unrelated_article, result.failure
  end

  test "일본어 번역이 실패해도 무관 기사 정리는 실행된다" do
    article = articles(:ruby_article)
    article.update!(is_related: false, title_ko: "제목", summary_body: "요약")

    service = ArticleAgentsService.new
    service.define_singleton_method(:run_japanese) { |_a| Dry::Monads::Failure(:japanese_agent_failed) }
    service.define_singleton_method(:ensure_body) { |a| Dry::Monads::Success(a) }
    service.define_singleton_method(:run_embed) { |a| Dry::Monads::Success(a) }
    service.define_singleton_method(:run_humanize) { |a| Dry::Monads::Success(a) }
    service.define_singleton_method(:run_thumbnail) { |a| Dry::Monads::Success(a) }

    # Pinned to `nil` by the initial assignment otherwise, which rejects the
    # assignment made inside the block below.
    result = nil #: Dry::Monads::Result?
    Articles::AgentRunner.stub(:run, ->(**) { Dry::Monads::Success(article) }) do
      result = service.call(article)
    end

    assert_predicate result, :failure?
    assert_equal :japanese_agent_failed, result.failure
    assert_predicate article.reload, :discarded?
  end

  test "run_humanize는 over_polish_aborted=true이면 article을 갱신하지 않고 실패를 반환한다" do
    article = articles(:ruby_article)
    article.update!(summary_body: "원본 요약")

    aborted_response = llm_message({
      "summary_key" => [],
      "summary_detail" => {},
      "summary_body" => "원본 요약",
      "over_polish_aborted" => true
    })

    chat = build_humanize_chat(aborted_response)

    result = nil
    HumanMonolithAgent.stub(:chat, chat) do
      result = ArticleAgentsService.new.send(:run_humanize, article)
    end

    assert_predicate result, :failure?
    assert_equal "원본 요약", article.reload.summary_body
  end

  # 모델이 JSON이 아닌 텍스트를 돌려주면 parsed가 JSON::ParserError를 낸다.
  # 이때 article을 건드리지 않고 실패로 끝나야 한다. (코드 펜스로 감싼 JSON은
  # Articles::AgentResponse.structured가 풀어 주므로 여기 해당하지 않는다.)
  test "run_humanize는 응답이 JSON이 아니면 article을 갱신하지 않고 실패를 반환한다" do
    article = articles(:ruby_article)
    article.update!(summary_body: "원본 요약")

    raw_response = raw_message("summary_body: 윤문된 본문")

    chat = build_humanize_chat(raw_response)

    result = nil
    HumanMonolithAgent.stub(:chat, chat) do
      result = ArticleAgentsService.new.send(:run_humanize, article)
    end

    assert_predicate result, :failure?
    assert_equal "원본 요약", article.reload.summary_body
  end

  # 번역 대상이 아닌 기사는 파이프라인 실패가 아니다. 판정은 ArticleJapaneseService가 한다.
  test "run_japanese는 한국어 요약이 없는 기사를 성공으로 건너뛴다" do
    article = articles(:ruby_article)
    article.update!(summary_body: nil)

    result = ArticleAgentsService.new.send(:run_japanese, article)

    assert_predicate result, :success?
    assert_nil article.reload.title_ja
  end

  test "run_japanese는 번역 실패를 그대로 돌려준다" do
    article = articles(:ruby_article)
    japanese_service = Object.new
    japanese_service.define_singleton_method(:call) { |_a| Dry::Monads::Failure(:japanese_agent_empty) }

    result = nil #: Dry::Monads::Result?
    ArticleJapaneseService.stub(:new, -> { japanese_service }) do
      result = ArticleAgentsService.new.send(:run_japanese, article)
    end

    assert_equal :japanese_agent_empty, result.failure
  end
end
