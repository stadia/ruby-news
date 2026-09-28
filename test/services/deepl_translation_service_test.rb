# frozen_string_literal: true

# rbs_inline: enabled

require "test_helper"

class DeeplTranslationServiceTest < ActiveSupport::TestCase
  setup do
    @original_auth_key = ENV.fetch("DEEPL_AUTH_KEY", nil)
    ENV["DEEPL_AUTH_KEY"] = "test-deepl-key"
  end

  teardown do
    ENV["DEEPL_AUTH_KEY"] = @original_auth_key
  end

  def with_deepl(response)
    Rails.stub(:cache, ActiveSupport::Cache::MemoryStore.new) do
      DeepL.stub(:translate, response) do
        yield DeeplTranslationService.new
      end
    end
  end

  # `translate` and `validate_deepl_available` are protected, so they are
  # stubbed per-instance the way the sibling ArticleAgentsService tests do it
  # rather than through the DeepL client or ENV.
  def build_service(outputs)
    service = DeeplTranslationService.new
    service.define_singleton_method(:validate_deepl_available) { |a| Dry::Monads::Success(a) }
    service.define_singleton_method(:translate) { |_texts, context: nil| outputs }
    service
  end

  def translatable_article
    article = articles(:ruby_article)
    article.update!(title_ko: "제목", summary_body: "본문", summary_key: [], summary_detail: {})
    article
  end

  test "DeepL이 nil 번역을 섞어 반환하면 실패를 돌려준다" do
    article = translatable_article
    # Same length as the input, so the existing size check does not catch it --
    # one element simply has no text.
    result = build_service([ nil, "はじめに", "むすび", "本文" ]).call(article)

    assert_predicate result, :failure?
    assert_equal :deepl_error, result.failure
  end

  # The regression this guards: with `.to_s` and no nil check, the nil above
  # became "" and the service returned Success. ArticleJapaneseService takes a
  # Success at face value (`return attrs if attrs.is_a?(Hash)`), so the
  # ArticleJapaneseAgent fallback would be skipped and empty Japanese columns
  # could be persisted -- invisible to readers, who then see the Korean text
  # via `summary_body_ja.presence || summary_body`.
  test "nil 번역 실패는 ArticleJapaneseAgent 폴백으로 이어진다" do
    article = translatable_article

    japanese = ArticleJapaneseService.new
    japanese.define_singleton_method(:japanese_via_agent) do |_a|
      { title_ja: "エージェント題", summary_body_ja: "エージェント本文" }
    end

    # Wrapped in a lambda: minitest's `stub` *calls* a replacement value that
    # responds to `call`, and a service instance does -- passing it directly
    # would invoke `service.call` with no arguments.
    stubbed = build_service([ nil, "はじめに", "むすび", "本文" ])

    attrs = nil #: Hash[Symbol, untyped]?
    DeeplTranslationService.stub(:new, -> { stubbed }) do
      attrs = japanese.send(:japanese_translation, article)
    end

    assert_equal "エージェント題", attrs[:title_ja]
  end

  # nil 검사가 scalar 영역만 볼 때 놓치던 경로: summary_key 번역 원소의 nil도
  # 폴백 대상 실패여야 한다(그렇지 않으면 일본어 요약 항목이 조용히 유실된다).
  test "summary_key 번역 원소가 nil이어도 실패를 돌려준다" do
    article = translatable_article
    article.update!(summary_key: [ "핵심" ])

    # scalars 4개는 정상, summary_key 영역 마지막 원소만 nil
    result = build_service([ "題", "はじめに", "むすび", "本文", nil ]).call(article)

    assert_predicate result, :failure?
    assert_equal :deepl_error, result.failure
  end

  test "모든 번역이 채워져 있으면 성공을 돌려준다" do
    article = translatable_article
    result = build_service([ "題", "はじめに", "むすび", "本文" ]).call(article)

    assert_predicate result, :success?
    assert_equal "題", result.value![:title_ja]
    assert_equal "はじめに", result.value![:summary_detail_ja]["introduction"]
  end

  test "입력 순서와 빈 텍스트 위치를 유지하고 번역 결과를 정리한다" do
    article = translatable_article
    article.update!(title_ko: " 제목 ", summary_key: [ "핵심", "", " ", "둘째" ],
                    summary_detail: { "introduction" => "서론", "conclusion" => "" })
    responses = [ " 題 ", " はじめに ", " ", " 本文 ", " 要点 ", " " ].map do |text|
      DeepL::Resources::Text.new(text, "KO", nil, nil, nil)
    end
    client = lambda do |texts, source, target, context:|
      assert_equal [ " 제목 ", "서론", " ", "본문", "핵심", "둘째" ], texts
      assert_equal "KO", source
      assert_equal "JA", target
      assert_equal "IT·기술 뉴스 기사 / 제목", context
      responses
    end

    with_deepl(client) do |service|
      result = service.call(article)

      assert_predicate result, :success?
      assert_equal({ title_ja: "題", summary_key_ja: [ "要点" ],
                     summary_detail_ja: { "introduction" => "はじめに", "conclusion" => "" },
                     summary_body_ja: "本文" }, result.value!)
    end
  end

  test "번역 응답 개수가 입력보다 적거나 많으면 실패한다" do
    article = translatable_article

    [ [ "題" ], [ "題", "서론", "결론", "본문", "초과" ] ].each do |outputs|
      result = build_service(outputs).call(article)

      assert_predicate result, :failure?
      assert_equal :deepl_error, result.failure
    end
  end

  test "DeepL이 nil 응답을 반환하면 실패한다" do
    with_deepl(nil) do |service|
      result = service.call(translatable_article)

      assert_predicate result, :failure?
      assert_equal :deepl_error, result.failure
    end
  end

  test "API 키가 없으면 DeepL을 호출하지 않고 설정 실패를 반환한다" do
    ENV.delete("DEEPL_AUTH_KEY")
    with_deepl(->(*) { flunk "설정 없이 DeepL을 호출함" }) do |service|
      result = service.call(translatable_article)

      assert_predicate result, :failure?
      assert_equal :not_configured, result.failure
    end
  end

  test "일반 API 오류는 쿼터 차단 없이 번역 실패를 반환한다" do
    with_deepl(->(*) { raise StandardError, "network failure" }) do |service|
      result = service.call(translatable_article)

      assert_predicate result, :failure?
      assert_equal :deepl_error, result.failure
      assert_not Rails.cache.exist?(DeeplTranslationService::QUOTA_CACHE_KEY)
    end
  end

  test "한도 초과는 월말까지 후속 호출을 막고 다음 달에 해제한다" do
    article = translatable_article
    responses = [ "題", "序", "結", "本文" ].map do |text|
      DeepL::Resources::Text.new(text, "KO", nil, nil, nil)
    end
    calls = 0
    client = lambda do |*|
      calls += 1
      raise DeepL::Exceptions::QuotaExceeded, "quota" if calls == 1

      responses
    end

    travel_to Time.zone.local(2026, 9, 15, 12) do
      with_deepl(client) do |service|
        result = service.call(article)

        assert_predicate result, :failure?
        assert_equal :quota_exceeded, result.failure

        blocked = service.call(article)

        assert_predicate blocked, :failure?
        assert_equal :quota_exceeded, blocked.failure
        assert_equal 1, calls

        travel_to Time.zone.local(2026, 10, 1)

        assert_predicate service.call(article), :success?
        assert_equal 2, calls
      end
    end
  end
end
