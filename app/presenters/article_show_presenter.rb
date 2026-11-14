# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

# 기사 상세(show) 화면의 표시 판단을 모아둔다.
# display_summary_* 는 로케일 폴백에 따라 Hash/Array/nil 이 섞여 들어오므로,
# 뷰가 타입 분기를 하지 않도록 여기서 정규화한다.
class ArticleShowPresenter
  #: (Article article, ?host: String?) -> void
  def initialize(article, host: nil)
    @article = article
    @host = host
  end

  attr_reader :article

  #: () -> bool
  def hero_thumbnail?
    article.thumbnail.attached?
  end

  # 요약 핵심 항목. Array 가 아니면 렌더하지 않는다.
  #: () -> Array[untyped]
  def summary_key_items
    return SolidCableJapaneseCorrection::KEY_POINTS if solid_cable_correction?

    items = article.display_summary_key
    items.is_a?(Array) ? items : []
  end

  #: () -> bool
  def summary_key_items?
    summary_key_items.any?
  end

  #: () -> String?
  def description
    return SolidCableJapaneseCorrection::KEY_POINTS.first if solid_cable_correction?

    article.summary_key_preview
  end

  # 상세 요약은 Hash 일 때만 본문/서론/결론을 렌더한다.
  #: () -> bool
  def summary_detail?
    solid_cable_correction? || article.display_summary_detail.is_a?(Hash)
  end

  #: () -> String?
  def introduction
    return SolidCableJapaneseCorrection::INTRODUCTION if solid_cable_correction?

    summary_detail_value("introduction")
  end

  #: () -> String?
  def conclusion
    return SolidCableJapaneseCorrection::CONCLUSION if solid_cable_correction?

    summary_detail_value("conclusion")
  end

  #: () -> String?
  def summary_body
    return SolidCableJapaneseCorrection::BODY if solid_cable_correction?

    return nil unless summary_detail?

    article.display_summary_body.presence
  end

  #: () -> String?
  def published_at_iso
    article.published_at&.iso8601
  end

  #: (?Symbol format) -> String?
  def published_at_label(format = :short)
    published_at = article.published_at
    return nil if published_at.nil?

    I18n.l(published_at, format:)
  end

  private

  #: () -> bool
  def solid_cable_correction?
    @host == SolidCableJapaneseCorrection::HOST &&
      I18n.locale == :ja &&
      article.slug == SolidCableJapaneseCorrection::SLUG
  end

  #: (String key) -> String?
  def summary_detail_value(key)
    return nil unless summary_detail?

    article.display_summary_detail[key].presence
  end
end
