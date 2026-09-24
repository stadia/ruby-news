# frozen_string_literal: true

# rbs_inline: enabled

require "test_helper"

class DeeplTranslationServiceTest < ActiveSupport::TestCase
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
end
