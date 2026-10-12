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

  def assert_logged(messages, *fragments)
    assert messages.any? { |message| fragments.all? { message.include?(it) } }, "#{fragments} 로그가 없다: #{messages}"
  end

  # 서비스의 logger(OperationService#logger)가 Rails.logger이므로 해당 레벨 메서드를
  # 스텁해 메시지를 모은다. 다른 레벨은 스텁하지 않아 레벨이 바뀌면 단언이 실패한다.
  def capture_logs(level)
    messages = []
    Rails.logger.stub(level, ->(message = nil, *_rest, &block) { messages << (message || block&.call).to_s }) { yield }
    messages
  end

  test "서비스는 OperationService를 상속한다" do
    service = ArticleAgentsService.new

    assert_kind_of OperationService, service
  end

  test "서비스는 요약 프롬프트를 AgentRunner에 전달한다" do
    article = articles(:ruby_article)
    article.body = "한국어 요약을 위한 기사 본문입니다. " * 10
    expected_prompt = Articles::SummaryPrompt.build(article)
    captured_prompt = nil
    service = ArticleAgentsService.new
    service.define_singleton_method(:ensure_body) { |a| Dry::Monads::Success(a) }
    service.define_singleton_method(:run_embed) { |a| Dry::Monads::Success(a) }

    Articles::AgentRunner.stub(:run, ->(article:, prompt:) {
      captured_prompt = prompt
      Dry::Monads::Failure(:stop_after_prompt)
    }) do
      service.call(article)
    end

    assert_equal expected_prompt, captured_prompt
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

  # 일시적인 본문 수집 실패로 기사를 지우지 않는다. ArticleBatchJob이 다시 집는다(#1099).
  test "본문 수집이 일시적으로 실패하면 discard하지 않고 사유를 남긴다" do
    article = articles(:ruby_article)
    article.update!(body: nil)
    content_service = Object.new
    content_service.define_singleton_method(:call) { |_article = nil| Dry::Monads::Failure(:fetch_failed) }

    result = nil #: Dry::Monads::Result?
    warnings = capture_logs(:warn) do
      ContentService.stub(:new, -> { content_service }) { result = ArticleAgentsService.new.call(article) }
    end

    assert_equal :fetch_failed, result.failure
    assert_not_predicate article.reload, :discarded?
    assert_logged warnings, "article #{article.id}", article.url, "fetch_failed"
  end

  # 영구 실패는 기존대로 폐기한다. 일시 실패 집합에 섞이면 SSRF 차단 URL까지 계속 재시도된다.
  %i[no_content blocked_url not_youtube].each do |reason|
    test "본문 수집이 #{reason}로 실패하면 discard한다" do
      article = articles(:ruby_article)
      article.update!(body: nil)
      content_service = Object.new
      content_service.define_singleton_method(:call) { |_article = nil| Dry::Monads::Failure(reason) }

      result = nil #: Dry::Monads::Result?
      ContentService.stub(:new, -> { content_service }) { result = ArticleAgentsService.new.call(article) }

      assert_equal reason, result.failure
      assert_predicate article.reload, :discarded?
    end
  end

  # 이틀 넘게 일시 실패하는 기사는 오분류일 수 있다. 재시도 기간이 끝나면 kept 상태로 남으므로
  # error로 올려 알 수 있게 한다.
  test "오래 일시 실패한 기사는 재시도 종료 시각과 함께 error로 남긴다" do
    article = articles(:ruby_article)
    article.update!(body: nil, created_at: 50.hours.ago)
    content_service = Object.new
    content_service.define_singleton_method(:call) { |_article = nil| Dry::Monads::Failure(:fetch_failed) }

    errors = capture_logs(:error) do
      ContentService.stub(:new, -> { content_service }) { ArticleAgentsService.new.call(article) }
    end

    assert_logged errors, "article #{article.id}", article.url, "retries stop"
    assert_not_predicate article.reload, :discarded?
  end

  # 폐기는 공개 사이트와 연합에 Delete를 전파하므로 사유가 로그에 남아야 한다.
  test "본문을 얻지 못해 discard할 때 사유를 로그로 남긴다" do
    article = articles(:ruby_article)
    article.update!(body: nil)
    content_service = Object.new
    content_service.define_singleton_method(:call) { |_article = nil| Dry::Monads::Failure(:no_content) }

    warnings = capture_logs(:warn) do
      ContentService.stub(:new, -> { content_service }) { ArticleAgentsService.new.call(article) }
    end

    assert_logged warnings, "Discarding article #{article.id}", "no_content"
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

  # 본문 확보 단계의 일시적·검증 실패는 기사를 지울 사유가 아니다. 폐기하면 Delete가
  # 연합에 전파되지만, 남겨 두면 ArticleBatchJob이 title_ko가 없는 기사를 다시 집는다.
  test "가져온 본문과 함께 기사를 저장하지 못하면 discard하지 않고 :article_save_failed를 반환한다" do
    article = articles(:ruby_article)
    article.update!(body: nil)
    original_url = article.url
    article.url = articles(:similar_article).url # uniqueness 검증 실패를 만든다

    content_service = Object.new
    content_service.define_singleton_method(:call) { |_article = nil| Dry::Monads::Success("가져온 기사 본문입니다. " * 5) }

    result = nil #: Dry::Monads::Result?
    errors = capture_logs(:error) do
      ContentService.stub(:new, -> { content_service }) do
        result = ArticleAgentsService.new.call(article)
      end
    end

    assert_equal :article_save_failed, result.failure
    assert_not_predicate article.reload, :discarded?
    assert_nil article.body
    assert_equal original_url, article.url
    assert_logged errors, "article #{article.id}", "ActiveRecord::RecordInvalid"
  end

  # 저장하지 못한 변경이 메모리에 남으면 이후 단계의 update가 검증 없이 함께 저장할 수 있다.
  test "본문 저장에 실패하면 메모리상 article을 원래 값으로 되돌린다" do
    article = articles(:ruby_article)
    article.update!(body: nil)
    article.url = articles(:similar_article).url

    content_service = Object.new
    content_service.define_singleton_method(:call) { |_article = nil| Dry::Monads::Success("가져온 기사 본문입니다. " * 5) }

    ContentService.stub(:new, -> { content_service }) { ArticleAgentsService.new.call(article) }

    assert_not_predicate article, :changed?
    assert_nil article.body
  end

  test "본문 확보 중 예외가 나면 discard하지 않고 :ensure_body_failed를 반환한다" do
    article = articles(:ruby_article)
    article.update!(body: nil)
    content_service = Object.new
    content_service.define_singleton_method(:call) { |_article = nil| raise Faraday::TimeoutError, "timed out" }

    result = nil #: Dry::Monads::Result?
    errors = capture_logs(:error) do
      ContentService.stub(:new, -> { content_service }) { result = ArticleAgentsService.new.call(article) }
    end

    assert_equal :ensure_body_failed, result.failure
    assert_not_predicate article.reload, :discarded?
    assert_logged errors, "article #{article.id}", "Faraday::TimeoutError"
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
      "summary_key" => [ "다른 요점" ],
      "summary_detail" => {},
      "summary_body" => "롤백 전에 모델이 쓴 다른 본문",
      "over_polish_aborted" => true
    })

    chat = build_humanize_chat(aborted_response)

    result = nil
    infos = capture_logs(:info) do
      HumanMonolithAgent.stub(:chat, chat) do
        result = ArticleAgentsService.new.send(:run_humanize, article)
      end
    end

    assert_equal :humanize_aborted, result.failure
    assert_equal "원본 요약", article.reload.summary_body
    assert_logged infos, "article #{article.id}", "humanize_aborted"
  end

  # 모델이 JSON이 아닌 텍스트를 돌려주면 parsed가 JSON::ParserError를 낸다.
  # 이때 article을 건드리지 않고 :humanize_invalid_response로 끝나며, 사유가 warn 로그에
  # 남아야 한다. (코드 펜스로 감싼 JSON은 Articles::AgentResponse.structured가 풀어
  # 주므로 여기 해당하지 않는다.)
  test "run_humanize는 응답이 JSON이 아니면 article을 갱신하지 않고 실패를 반환한다" do
    article = articles(:ruby_article)
    article.update!(summary_body: "원본 요약")

    raw_response = raw_message("summary_body: 윤문된 본문")

    chat = build_humanize_chat(raw_response)

    result = nil
    warnings = capture_logs(:warn) do
      HumanMonolithAgent.stub(:chat, chat) do
        result = ArticleAgentsService.new.send(:run_humanize, article)
      end
    end

    assert_equal :humanize_invalid_response, result.failure
    assert_equal "원본 요약", article.reload.summary_body
    assert_logged warnings, "article #{article.id}", "humanize_invalid_response"
  end

  test "run_humanize는 빈 요점 응답으로 기존 요점을 지우지 않는다" do
    article = articles(:ruby_article)
    article.update!(summary_key: [ "기존 요점" ], summary_body: "원본 요약")

    chat = build_humanize_chat(llm_message({ "summary_key" => [], "summary_body" => "다듬은 요약" }))

    result = nil
    HumanMonolithAgent.stub(:chat, chat) do
      result = ArticleAgentsService.new.send(:run_humanize, article)
    end

    assert_predicate result, :success?
    assert_equal [ "기존 요점" ], article.reload.summary_key
    assert_equal "다듬은 요약", article.summary_body
  end

  # 에이전트 호출·DB 저장 오류는 모두 :humanize_failed지만, 로그에 예외 클래스를
  # 남겨 원인을 구분할 수 있어야 한다.
  test "run_humanize는 예외가 나면 예외 클래스를 로그에 남기고 :humanize_failed를 반환한다" do
    article = articles(:ruby_article)
    chat = Object.new
    chat.define_singleton_method(:with_skills) { self }
    chat.define_singleton_method(:ask) { |_prompt| raise Faraday::TimeoutError, "timed out" }

    result = nil
    errors = capture_logs(:error) do
      HumanMonolithAgent.stub(:chat, chat) do
        result = ArticleAgentsService.new.send(:run_humanize, article)
      end
    end

    assert_equal :humanize_failed, result.failure
    assert_logged errors, "article #{article.id}", "Faraday::TimeoutError"
  end

  test "run_humanize는 저장에 실패하면 메모리상 윤문 필드를 원래 값으로 되돌린다" do
    article = articles(:ruby_article)
    article.update!(summary_key: [ "기존 요점" ], summary_body: "원본 요약")
    article.url = articles(:similar_article).url # update!가 검증에서 실패하도록 한다

    chat = build_humanize_chat(llm_message({ "summary_key" => [ "새 요점" ], "summary_body" => "다듬은 요약" }))

    result = nil
    errors = capture_logs(:error) do
      HumanMonolithAgent.stub(:chat, chat) do
        result = ArticleAgentsService.new.send(:run_humanize, article)
      end
    end

    assert_equal :humanize_failed, result.failure
    assert_equal "원본 요약", article.summary_body # reload 없이 메모리 값을 본다
    assert_equal [ "기존 요점" ], article.summary_key
    assert_logged errors, "article #{article.id}", "ActiveRecord::RecordInvalid"
  end

  test "run_humanize는 비정상 상세 응답으로 기존 상세를 지우지 않는다" do
    article = articles(:ruby_article)
    article.update!(summary_detail: { "introduction" => "기존 도입", "conclusion" => "기존 결론" }, summary_body: "원본 요약")

    chat = build_humanize_chat(llm_message({
      "summary_detail" => { "introduction" => "", "conclusion" => "" }, "summary_body" => "다듬은 요약"
    }))

    HumanMonolithAgent.stub(:chat, chat) { ArticleAgentsService.new.send(:run_humanize, article) }

    assert_equal({ "introduction" => "기존 도입", "conclusion" => "기존 결론" }, article.reload.summary_detail)
    assert_equal "다듬은 요약", article.summary_body
  end

  # 윤문은 품질을 높이는 보조 단계라 어떤 사유로 건너뛰어도 이후 단계와 기존 요약이 유지돼야 한다.
  {
    "과윤문 롤백" => -> { { "over_polish_aborted" => true, "summary_body" => "다른 본문" }.to_json },
    "JSON이 아닌 응답" => -> { "summary_body: 윤문본" },
    "비어 있는 본문" => -> { { "summary_body" => " " }.to_json }
  }.each do |name, content|
    test "윤문이 #{name}로 건너뛰어도 일본어 번역까지 진행하고 기존 요약을 유지한다" do
      article = articles(:ruby_article)
      article.update!(body: "본문 문장입니다. " * 10, summary_key: [ "요점" ], title_ko: "테스트 제목", summary_body: "요약 본문")

      agent_response = llm_message({ "is_related" => true })
      agent = Object.new
      agent.define_singleton_method(:ask) { |_| agent_response }
      humanize_chat = build_humanize_chat(raw_message(content.call))

      japanese_called = false
      japanese_service = ArticleJapaneseService.new
      japanese_service.define_singleton_method(:japanese_translation) do |_article|
        japanese_called = true
        { title_ja: "テスト", summary_body_ja: "要約" }
      end
      embed_result = Struct.new(:vectors).new(Array.new(3072, 0.0))

      result = nil #: Dry::Monads::Result?
      RubyLLM.stub(:embed, ->(*, **) { embed_result }) do
        ArticleAgent.stub(:new, agent) do
          HumanMonolithAgent.stub(:chat, humanize_chat) do
            ArticleJapaneseService.stub(:new, -> { japanese_service }) do
              result = ArticleAgentsService.new.call(article)
            end
          end
        end
      end

      assert_predicate result, :success?
      assert japanese_called, "윤문을 건너뛴 뒤 일본어 번역이 호출되지 않았다"
      assert_equal "요약 본문", article.reload.summary_body
    end
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
