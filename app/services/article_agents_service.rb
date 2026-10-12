# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

class ArticleAgentsService < OperationService
  # 에이전트가 무관하다고 판정하면 자동 정리하는 수집원. 사람이 직접 등록하는 경로는
  # 오판으로 지우면 안 되므로 제외한다.
  AUTO_DISCARD_CLIENTS = %w[hacker_news rss gmail rss_page].freeze

  #: (Article article) -> Dry::Monads::Result
  def call(article)
    step ensure_body(article)
    step run_embed(article)
    step Articles::AgentRunner.run(article:, prompt: Articles::SummaryPrompt.build(article))
    run_humanize(article) # 실패해도 원문 요약은 유효하므로 이후 단계를 계속 진행한다(사유는 run_humanize가 로그로 남긴다)
    run_thumbnail(article) # 썸네일은 부가 산출물이라 실패해도 일본어 번역까지 진행한다
    japanese_result = run_japanese(article)
    discard_unrelated(article) # 정리는 모든 산출물 생성이 끝난 뒤 마지막에 한다
    step japanese_result
  end

  protected

  # 무관 기사 정리. 중간에 discard하면 이후 단계들이 discarded? 가드에 걸려 건너뛰므로
  # 파이프라인 맨 끝에서 처리한다. is_related는 ArticleSchema의 필수 필드라
  # AgentRunner가 성공하면 항상 컬럼에 반영돼 있다.
  #: (Article article) -> Dry::Monads::Result
  def discard_unrelated(article)
    return Success(article) unless unrelated_auto_discard?(article)

    article.discard!
    logger.info "Discarded unrelated article #{article.id}"
    Success(article)
  end

  # 파이프라인 끝에서 정리될 기사인지 미리 판정한다. 비용이 큰 썸네일 생성을
  # 건너뛰는 데도 쓰이므로 정리 조건과 반드시 같은 곳에서 나와야 한다.
  #: (Article article) -> bool
  def unrelated_auto_discard?(article)
    return false if article.discarded? || article.is_related

    AUTO_DISCARD_CLIENTS.include?(article.site&.client)
  end

  #: (Article article) -> Dry::Monads::Result
  def ensure_body(article)
    body = article.body
    return Success(article) if body.present? && body.size > 30

    body_result = ContentService.new.call(article)
    if body_result.failure?
      article.discard!
      return body_result
    end

    fetched_body = body_result.value!
    # 본문을 가져왔더라도 요약할 내용이 없을 만큼 짧으면 폐기한다.
    # Success에 .failure를 부르면 nil이 되어 실패 사유가 사라지므로 사유를 직접 지정한다.
    if fetched_body.size < 31
      article.discard!
      return Failure(:short_body)
    end

    article.update!(body: fetched_body)
    Success(article)
  rescue StandardError => e
    logger.error "Failed to ensure body for article #{article.id}: #{e.class}: #{e.message}"
    # discard!는 검증 없이 레코드 전체를 저장하므로, 저장에 실패한 변경을 먼저 되돌린다.
    article.restore_attributes
    article.discard!
    Failure(e.message)
  end

  #: (Article article) -> Dry::Monads::Result
  def run_embed(article)
    return Success(article) if article.embedding.present?

    # Generate embeddings if not present and body exists
    begin
      embedded_body = RubyLLM.embed(
        article.body,
        model: Articles::HybridSearch::EMBED_MODEL, # Google's model (입력 8192 토큰)
        dimensions: Articles::HybridSearch::EMBED_DIMENSIONS # MRL full 3072차원 (halfvec 컬럼)
      )
      article.update_column(:embedding, embedded_body.vectors.to_a) # Skip callbacks for performance
      Success(article)
    rescue StandardError => e
      logger.error "Failed to generate embeddings for article #{article.id}: #{e.message}"
      Failure(:embedding_failed)
    end
  end

  #: (Article article) -> Dry::Monads::Result
  def run_humanize(article)
    prompt = ArticleHumanizer.prompt(article)
    message = HumanMonolithAgent.chat.with_skills.ask(prompt)
    content = Articles::AgentResponse.structured(message)
    extraction = ArticleHumanizer.extract(content)
    skip_reason = extraction.skip_reason
    return skip_humanize(article, skip_reason, content) if skip_reason

    logger.info "Humanize metrics for article #{article.id}: #{content['metrics']}"
    article.update!(extraction.attributes)
    Success(article)
  rescue StandardError => e
    logger.error "Failed to humanize article #{article.id}: #{e.class}: #{e.message}"
    Failure(:humanize_failed)
  end

  # call은 윤문 실패를 무시하고 진행하므로, 윤문을 건너뛴 기사를 사유와 함께 여기서 남긴다.
  # 과윤문 롤백은 모델의 정상 판단이라 info, 응답이 계약을 어긴 경우는 warn이다.
  #: (Article article, Symbol reason, untyped content) -> Dry::Monads::Result
  def skip_humanize(article, reason, content)
    message = "Humanize skipped for article #{article.id}: #{reason} (response #{content.class})"
    reason == :humanize_aborted ? logger.info(message) : logger.warn(message)
    Failure(reason)
  end

  # 번역은 admin에서도 호출하는 ArticleJapaneseService가 맡는다. 번역 대상이 아닌 기사는
  # 파이프라인 실패가 아니므로 성공으로 넘긴다.
  #: (Article article) -> Dry::Monads::Result
  def run_japanese(article)
    result = ArticleJapaneseService.new.call(article)
    return Success(article) if result.failure? && ArticleJapaneseService::NOT_TRANSLATABLE.include?(result.failure)

    result
  end

  def run_thumbnail(article)
    if article.thumbnail.attached?
      logger.info "ArticleThumbnailJob skip: article #{article.id} already has thumbnail"
      return Success(article)
    end

    if article.discarded? || (article.slug.blank? || article.title_ko.blank?)
      logger.info "ArticleThumbnailJob skip: article #{article.id} is discarded or has no slug or title_ko"
      return Failure(:invalid_article)
    end

    # 어차피 파이프라인 끝에서 정리될 기사에는 AI 이미지 생성 비용을 쓰지 않는다.
    if unrelated_auto_discard?(article)
      logger.info "ArticleThumbnailJob skip: article #{article.id} will be discarded as unrelated"
      return Failure(:unrelated_article)
    end

    summary_key = article.summary_key
    if summary_key.blank? || !summary_key.is_a?(Array) || summary_key.empty?
      logger.info "ArticleThumbnailJob skip: article #{article.id} has no summary_key"
      return Failure(:no_summary_key)
    end

    if article.is_youtube? || Article.kept.confirmed.joins(:thumbnail_attachment).where(articles: { is_youtube: false, created_at: Time.zone.now.beginning_of_day.. }).count <= 5
      ArticleThumbnailJob.perform_later(article.id)
    else
      logger.info "ArticleThumbnailJob skip: thumbnail article count exceeded limit for article #{article.id}"
    end

    Success(article)
  end
end
