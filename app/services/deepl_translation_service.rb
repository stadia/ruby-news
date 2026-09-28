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
    keys = translation_keys(article)
    scalars = translation_scalars(article)
    inputs = scalars.values + keys
    outputs = translate(inputs, context: translation_context(article))
    return Failure(:deepl_error) if outputs.size != inputs.size

    scalar_out = scalars.keys.zip(outputs.first(scalars.size)).to_h
    key_out = outputs.last(keys.size)
    return Failure(:deepl_error) if nil_translation?(article, scalar_out, key_out)

    Success(translated_attributes(scalar_out, key_out))
  rescue DeepL::Exceptions::QuotaExceeded
    mark_quota_exceeded!
    logger.warn "DeepL quota exceeded for article #{article.id}; blocking DeepL until month reset"
    Failure(:quota_exceeded)
  rescue StandardError => e
    # DeepL 오류·네트워크 오류 모두 폴백 대상이므로 넓게 잡는다.
    logger.warn "DeepL translation failed for article #{article.id}: #{e.message}"
    Failure(:deepl_error)
  end

  #: (Article article) -> Array[String]
  def translation_keys(article)
    Array(article.summary_key).map(&:to_s).reject(&:blank?)
  end

  #: (Article article) -> Hash[Symbol, String]
  def translation_scalars(article)
    detail = article.summary_detail || {}
    {
      title_ja: article.title_ko.to_s,
      introduction: detail["introduction"].to_s,
      conclusion: detail["conclusion"].to_s,
      summary_body_ja: article.summary_body.to_s
    }
  end

  # nil을 빈 문자열로 바꾸면 ArticleJapaneseAgent 폴백을 건너뛰고 일본어 컬럼을
  # 비우거나 summary_key 항목을 유실하므로 scalar와 key 영역 모두 실패로 처리한다.
  #: (Article article, Hash[Symbol, String?] scalars, Array[String?] keys) -> bool
  def nil_translation?(article, scalars, keys)
    nil_labels = scalars.select { |_, value| value.nil? }.keys
    nil_labels << :summary_key_ja if keys.any?(&:nil?)
    return false if nil_labels.empty?

    logger.warn "DeepL returned a nil translation for article #{article.id} " \
                "(#{nil_labels.join(', ')}); falling back"
    true
  end

  #: (Hash[Symbol, String?] scalars, Array[String?] keys) -> Hash[Symbol, untyped]
  def translated_attributes(scalars, keys)
    {
      title_ja: scalars[:title_ja].to_s.strip,
      summary_key_ja: keys.map { |text| text.to_s.strip }.reject(&:blank?),
      summary_detail_ja: {
        "introduction" => scalars[:introduction].to_s.strip,
        "conclusion" => scalars[:conclusion].to_s.strip
      },
      summary_body_ja: scalars[:summary_body_ja].to_s.strip
    }
  end

  #: (Array[String] texts, ?context: String?) -> Array[String?]
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
