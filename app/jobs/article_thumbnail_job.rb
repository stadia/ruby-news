# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

# Article의 summary_key를 기반으로 썸네일 이미지를 생성하여 ActiveStorage에 첨부한다
class ArticleThumbnailJob < ApplicationJob
  queue_as :default

  #: (Integer article_id, ?force: bool) -> void
  def perform(article_id, force: false)
    article = Article.find_by(id: article_id)

    if article.nil?
      logger.info "ArticleThumbnailJob skip: article #{article_id} not found"
      return
    end

    if article.thumbnail.attached?
      if force
        article.thumbnail.purge
        logger.info "ArticleThumbnailJob purged existing thumbnail for article #{article_id} (force)"
      else
        # 썸네일은 이미 있지만 변형이 아직 처리 안 됐을 수 있다(이전 잡이 변형 처리
        # 단계에서 실패해 재시도된 경우 등). 생성은 건너뛰되 변형 처리를 다시 시도한다.
        process_thumbnail_variants(article)
        logger.info "ArticleThumbnailJob skip: article #{article_id} already has thumbnail"
        return
      end
    end

    if article.is_youtube?
      attach_youtube_thumbnail(article)
    else
      generate_ai_thumbnail(article)
    end

    process_thumbnail_variants(article) if article.thumbnail.attached?
  end

  private

  # 렌더 시 직접 CDN URL을 쓰려면 변형이 미리 처리돼 있어야 한다(미처리면 리다이렉트 폴백).
  # 이미 async 잡이므로 여기서 동기 처리해 첫 페이지 렌더의 지연/리다이렉트를 없앤다.
  # 에러는 잡지 않고 전파시킨다 — 변형 에러(Vips/S3 등)는 ApplicationJob의 retry_on
  # 대상이 아니라 잡이 실패로 남고(rescue_from이 로깅 후 re-raise), MissionControl에서
  # 수동 재시도하면 위 already-attached 분기가 썸네일 재생성 없이 변형만 다시 처리한다.
  #: (Article article) -> void
  def process_thumbnail_variants(article)
    Article::THUMBNAIL_VARIANTS.each_key do |name|
      article.thumbnail.variant(name).processed
    end
    logger.info "ArticleThumbnailJob processed thumbnail variants for article #{article.id}"
  end

  # YouTube 썸네일 해상도 후보 (높은 순)
  YOUTUBE_THUMBNAIL_QUALITIES = %w[maxresdefault sddefault hqdefault mqdefault default].freeze

  #: (Article article) -> void
  def attach_youtube_thumbnail(article)
    video_id = article.youtube_id
    if video_id.blank?
      logger.info "ArticleThumbnailJob skip: article #{article.id} has no youtube_id"
      return
    end

    response = fetch_youtube_thumbnail(video_id)
    if response.nil?
      logger.warn "ArticleThumbnailJob failed: no youtube thumbnail for article #{article.id}"
      return
    end

    article.thumbnail.attach(
      io: StringIO.new(response.body),
      filename: "thumbnail-#{article.id}.jpg",
      content_type: response.headers["content-type"] || "image/jpeg"
    )
    logger.info "ArticleThumbnailJob attached youtube thumbnail for article #{article.id}"
  end

  #: (String video_id) -> Faraday::Response?
  def fetch_youtube_thumbnail(video_id)
    YOUTUBE_THUMBNAIL_QUALITIES.each do |quality|
      url = "https://img.youtube.com/vi/#{video_id}/#{quality}.jpg"
      response = Faraday.get(url)
      # YouTube는 존재하지 않는 해상도에 120x90 placeholder를 반환하므로 크기로 판별
      return response if response.success? && response.body.bytesize > 5_000
    end
    nil
  end

  #: (Article article) -> void
  def generate_ai_thumbnail(article)
    summary_key = article.summary_key
    if summary_key.blank? || !summary_key.is_a?(Array) || summary_key.empty?
      logger.info "ArticleThumbnailJob skip: article #{article.id} has no summary_key"
      return
    end

    prompt = build_prompt(summary_key)
    message = ArticleImageAgent.new.ask(prompt)

    attachment = extract_image_attachment(message)
    if attachment.nil?
      logger.warn "ArticleThumbnailJob failed: no image generated for article #{article.id} (content=#{message.content.inspect.truncate(200)})"
      return
    end

    ext = MIME::Types[attachment.mime_type].first&.preferred_extension || "png"
    article.thumbnail.attach(
      io: StringIO.new(attachment.content),
      filename: "thumbnail-#{article.id}.#{ext}",
      content_type: attachment.mime_type
    )
    logger.info "ArticleThumbnailJob attached ai thumbnail for article #{article.id}"
  end

  # ruby_llm 2.0부터 생성 이미지는 content가 아니라 Message#attachments에 담긴다.
  #: (RubyLLM::Message message) -> RubyLLM::Attachment?
  def extract_image_attachment(message)
    message.attachments.find(&:image?) || message.attachments.first
  end

  #: (Array[String] summary_key) -> String
  def build_prompt(summary_key)
    points = summary_key.each_with_index.map { |s, i| "#{i + 1}. #{s}" }.join("\n")
    <<~PROMPT.strip
      다음은 기술 뉴스 기사의 핵심 요약이다. 이 요약을 인포그래픽 이미지 한 장으로 시각화한다.

      [요약]
      #{points}
    PROMPT
  end
end
