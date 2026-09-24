# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

# 한국어 기사 결과물을 DeepL API(공식 deepl-rb 젬)로 일본어 번역한다.
# 무료 한도 초과(HTTP 456)를 받으면 그 달 말까지 캐시 플래그로 DeepL 호출 자체를 막고
# Failure(:quota_exceeded)를 반환해, 호출 측이 ArticleJapaneseAgent로 폴백하도록 한다.
class DeeplTranslationService < OperationService
  QUOTA_CACHE_KEY = "deepl:quota_exceeded"
  SOURCE_LANG = "KO"
  TARGET_LANG = "JA"

  #: (Article article) -> Dry::Monads::Result
  def call(article)
    step validate_deepl_available(article)
    step run_translation(article)
  end

  protected

  # Dry::Operation의 call에서 return Failure(...)를 직접 반환하면 Success(Failure(...))로 감싸지므로
  # guard clause는 반드시 step으로 호출되는 별도 메서드에 위치시킨다.
  #: (Article article) -> Dry::Monads::Result
  def validate_deepl_available(article)
    return Failure(:not_configured) if ENV.fetch("DEEPL_AUTH_KEY", nil).blank?
    return Failure(:quota_exceeded) if quota_exceeded?

    Success(article)
  end

  #: (Article article) -> Dry::Monads::Result
  def run_translation(article)
    keys = Array(article.summary_key).map(&:to_s).reject(&:blank?)
    detail = article.summary_detail || {}
    scalars = {
      title_ja: article.title_ko.to_s,
      introduction: detail["introduction"].to_s,
      conclusion: detail["conclusion"].to_s,
      summary_body_ja: article.summary_body.to_s
    }

    inputs = scalars.values + keys
    outputs = translate(inputs, context: translation_context(article))
    return Failure(:deepl_error) if outputs.size != inputs.size

    scalar_out = scalars.keys.zip(outputs.first(scalars.size)).to_h

    # A nil element means DeepL answered with a translation object whose text
    # was null -- the size check above only catches a short response.
    #
    # This must stay a Failure. `japanese_translation` in ArticleJapaneseService
    # falls back to ArticleJapaneseAgent on failure, but takes a Success at
    # face value: `return attrs if attrs.is_a?(Hash)`. Letting the nils through
    # as "" would therefore skip the fallback entirely and either persist empty
    # Japanese columns (readers silently get the Korean text, because
    # `display_summary_body` is `summary_body_ja.presence || summary_body`) or
    # fail as `:japanese_agent_empty` -- a label naming an agent that was never
    # called.
    #
    # The `.to_s` below is then unreachable for nil and kept only so the
    # expression types as String; the recovery decision is made here.
    #
    # `summary_key` 영역(outputs의 뒷부분)의 nil도 같은 실패다 — 거기서 nil을
    # 통과시키면 `.to_s.strip`이 ""로 만들어 reject돼 일본어 요약 항목이 조용히 유실된다.
    if outputs.any?(&:nil?)
      nil_labels = scalar_out.select { |_, v| v.nil? }.keys
      nil_labels << :summary_key_ja if outputs.last(keys.size).any?(&:nil?)
      logger.warn "DeepL returned a nil translation for article #{article.id} " \
                  "(#{nil_labels.join(', ')}); falling back"
      return Failure(:deepl_error)
    end

    Success(
      title_ja: scalar_out[:title_ja].to_s.strip,
      summary_key_ja: outputs.last(keys.size).map { |t| t.to_s.strip }.reject(&:blank?),
      summary_detail_ja: {
        "introduction" => scalar_out[:introduction].to_s.strip,
        "conclusion" => scalar_out[:conclusion].to_s.strip
      },
      summary_body_ja: scalar_out[:summary_body_ja].to_s.strip
    )
  rescue DeepL::Exceptions::QuotaExceeded
    mark_quota_exceeded!
    logger.warn "DeepL quota exceeded for article #{article.id}; blocking DeepL until month reset"
    Failure(:quota_exceeded)
  rescue StandardError => e
    # DeepL 오류·네트워크 오류 모두 폴백 대상이므로 넓게 잡는다.
    logger.warn "DeepL translation failed for article #{article.id}: #{e.message}"
    Failure(:deepl_error)
  end

  #: (Array[String] texts, ?context: String?) -> Array[String]
  def translate(texts, context: nil)
    # DeepL은 빈 문자열을 거부할 수 있어 공백으로 치환해 인덱스 정렬을 유지한다.
    payload = texts.map { |text| text.presence || " " }
    # context는 번역되지 않고 참조용으로만 쓰여(과금 제외) 짧은 키워드의 도메인/중의성을 잡아준다.
    result = DeepL.translate(payload, SOURCE_LANG, TARGET_LANG, context: context.presence)
    Array(result).map(&:text)
  end

  # 기사 주제를 맥락으로 전달해 summary_key 등 짧은 텍스트의 용어·어조를 안정화한다.
  #: (Article article) -> String
  def translation_context(article)
    [ "IT·기술 뉴스 기사", article.title_ko.to_s.strip ].reject(&:blank?).join(" / ")
  end

  private

  # 한 번 한도를 넘기면 그 달 안에는 계속 456이므로, 월말까지 DeepL 호출을 막는다.
  #: () -> bool
  def quota_exceeded?
    Rails.cache.exist?(QUOTA_CACHE_KEY)
  end

  #: () -> void
  def mark_quota_exceeded!
    Rails.cache.write(QUOTA_CACHE_KEY, true, expires_in: seconds_until_month_reset)
  end

  #: () -> Float
  def seconds_until_month_reset
    [ Time.current.end_of_month - Time.current, 1.0 ].max
  end
end
