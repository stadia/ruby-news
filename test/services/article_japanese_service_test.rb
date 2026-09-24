# frozen_string_literal: true

# rbs_inline: enabled

require "test_helper"

class ArticleJapaneseServiceTest < ActiveSupport::TestCase
  def llm_message(payload)
    raw_message(payload.to_json)
  end

  def raw_message(content)
    RubyLLM::Message.new(role: :assistant, content:, finish_reason: "stop")
  end

  def translatable_article
    article = articles(:ruby_article)
    article.update!(title_ko: "테스트 제목", summary_body: "요약 본문")
    article
  end

  # DeepL은 ENV·네트워크에 의존하므로 결과만 고정한다. Minitest의 stub은 call에
  # 응답하는 값을 호출해 반환값으로 쓰므로, call을 가진 가짜 객체는 람다로 감싼다.
  def stub_deepl(result, &)
    deepl = Object.new
    deepl.define_singleton_method(:call) { |_article| result }
    DeeplTranslationService.stub(:new, -> { deepl }, &)
  end

  def stub_japanese_agent(response, &)
    agent = Object.new
    agent.define_singleton_method(:ask) { |_prompt| response }
    ArticleJapaneseAgent.stub(:new, agent, &)
  end

  test "서비스는 OperationService를 상속한다" do
    assert_operator ArticleJapaneseService, :<, OperationService
  end

  test "DeepL 번역 결과로 일본어 컬럼을 갱신한다" do
    article = translatable_article
    attrs = { title_ja: "テスト", summary_body_ja: "要約" }

    result = nil #: Dry::Monads::Result?
    stub_deepl(Dry::Monads::Success(attrs)) do
      result = ArticleJapaneseService.new.call(article)
    end

    assert_predicate result, :success?
    article.reload

    assert_equal "テスト", article.title_ja
    assert_equal "要約", article.summary_body_ja
  end

  test "DeepL이 실패하면 ArticleJapaneseAgent로 폴백한다" do
    article = translatable_article
    response = llm_message({ "title_ja" => "タイトル", "summary_body_ja" => "本文" })

    result = nil #: Dry::Monads::Result?
    stub_deepl(Dry::Monads::Failure(:quota_exceeded)) do
      stub_japanese_agent(response) do
        result = ArticleJapaneseService.new.call(article)
      end
    end

    assert_predicate result, :success?
    assert_equal "タイトル", article.reload.title_ja
  end

  test "번역 결과에 title_ja가 없으면 갱신하지 않고 실패를 반환한다" do
    article = translatable_article
    article.update!(title_ja: "既存")

    result = nil #: Dry::Monads::Result?
    stub_deepl(Dry::Monads::Failure(:deepl_error)) do
      stub_japanese_agent(raw_message("title_ja: タイトル")) do
        result = ArticleJapaneseService.new.call(article)
      end
    end

    assert_predicate result, :failure?
    assert_equal :japanese_agent_empty, result.failure
    assert_equal "既存", article.reload.title_ja
  end

  test "번역 중 예외가 나면 japanese_agent_failed를 반환한다" do
    article = translatable_article
    deepl = Object.new
    deepl.define_singleton_method(:call) { |_article| raise "boom" }

    result = nil #: Dry::Monads::Result?
    DeeplTranslationService.stub(:new, -> { deepl }) do
      result = ArticleJapaneseService.new.call(article)
    end

    assert_predicate result, :failure?
    assert_equal :japanese_agent_failed, result.failure
  end

  test "폐기된 기사는 번역하지 않는다" do
    article = translatable_article
    article.discard!

    result = ArticleJapaneseService.new.call(article)

    assert_predicate result, :failure?
    assert_equal :discarded, result.failure
  end

  test "한국어 제목이나 요약이 없으면 번역하지 않는다" do
    article = translatable_article
    article.update!(summary_body: nil)

    result = ArticleJapaneseService.new.call(article)

    assert_predicate result, :failure?
    assert_equal :missing_korean_summary, result.failure
  end

  test "japanese_via_agent는 JSON 응답을 번역 속성으로 바꾼다" do
    article = articles(:ruby_article)

    attrs = nil
    stub_japanese_agent(llm_message({ "title_ja" => "タイトル", "summary_body_ja" => "本文" })) do
      attrs = ArticleJapaneseService.new.send(:japanese_via_agent, article)
    end

    assert_equal({ title_ja: "タイトル", summary_body_ja: "本文" }, attrs)
  end

  test "japanese_via_agent는 코드 펜스로 감싼 JSON 응답도 번역 속성으로 바꾼다" do
    article = articles(:ruby_article)
    payload = { "title_ja" => "タイトル", "summary_key" => [ "要点" ], "summary_body" => "本文" }

    attrs = nil
    stub_japanese_agent(raw_message("```json\n#{JSON.pretty_generate(payload)}\n```")) do
      attrs = ArticleJapaneseService.new.send(:japanese_via_agent, article)
    end

    assert_equal({ title_ja: "タイトル", summary_key_ja: [ "要点" ], summary_body_ja: "本文" }, attrs)
  end

  test "japanese_via_agent는 응답이 JSON이 아니면 빈 해시를 반환한다" do
    article = articles(:ruby_article)

    attrs = nil
    stub_japanese_agent(raw_message("title_ja: タイトル")) do
      attrs = ArticleJapaneseService.new.send(:japanese_via_agent, article)
    end

    assert_empty attrs
  end
end
