# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

class ArticleAgentsService < OperationService
  # 에이전트가 무관하다고 판정하면 자동 정리하는 수집원. 사람이 직접 등록하는 경로는
  # 오판으로 지우면 안 되므로 제외한다.
  AUTO_DISCARD_CLIENTS = %w[hacker_news rss gmail rss_page].freeze
  # 이보다 오래 일시 실패한 기사는 재시도 기간(ArticleBatchJob::LOOKBACK)이 곧 끝나므로 error로 알린다.
  STALE_RETRY_AGE = 2.days

  #: (Article article) -> Dry::Monads::Result
  def call(article)
    step ensure_body(article)
    step run_embed(article)
    step Articles::AgentRunner.run(article:, prompt: Articles::SummaryPrompt.build(article))
    # 윤문은 품질을 높이는 보조 단계다. 실패해도 원문 요약은 유효하므로 이후 단계를 계속
    # 진행하고, 결과(반영·건너뜀·실패)는 run_humanize가 로그와 humanize_status에 남긴다.
    run_humanize(article)
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

  # 본문을 얻지 못했거나 요약할 만큼 길지 않으면 수집 대상이 아니므로 폐기한다. 폐기는
  # 공개 사이트와 연합에 Delete를 전파하므로 그 두 경우로만 한정하고, 일시적인 수집 실패
  # (ContentService::TRANSIENT_FAILURES), 저장 실패, 예외는 기사를 남긴 채 Failure로
  # 끝낸다. 재시도는 keep_for_retry 참고.
  #: (Article article) -> Dry::Monads::Result
  def ensure_body(article)
    body = article.body
    return Success(article) if body.present? && body.size > 30

    body_result = ContentService.new.call(article)
    # Success#failure는 nil이고 TRANSIENT_FAILURES에는 nil이 없으므로 failure?를 먼저 보지 않아도 된다.
    return keep_for_retry(article, body_result.failure) if ContentService::TRANSIENT_FAILURES.include?(body_result.failure)
    return discard_with(article, body_result.failure) if body_result.failure?

    fetched_body = body_result.value!
    # 본문을 가져왔더라도 요약할 내용이 없을 만큼 짧으면 폐기한다.
    return discard_with(article, :short_body) if fetched_body.size < 31

    save_body(article, fetched_body)
  rescue StandardError => e
    logger.error "Failed to ensure body for article #{article.id}: #{e.class}: #{e.message}"
    Failure(:ensure_body_failed)
  end

  # 실패를 예외로 올려 저장하지 못한 본문을 모른 채 요약·임베딩으로 넘어가지 않게 한다.
  # body에는 검증이 없으므로 실패 원인은 본문이 아니라 레코드다(url·slug 중복 검증, DB 오류).
  # 되돌리지 않으면 메모리에 남은 변경을 이후 단계의 save가 함께 저장할 수 있다.
  #: (Article article, String body) -> Dry::Monads::Result
  def save_body(article, body)
    article.update!(body:)
    Success(article)
  rescue StandardError => e
    article.restore_attributes
    logger.error "Failed to save article #{article.id} with fetched body: #{e.class}: #{e.message}"
    Failure(:article_save_failed)
  end

  # 일시적인 수집 실패는 폐기하지 않는다. title_ko가 없는 기사는 ArticleBatchJob이 생성 후
  # LOOKBACK(3일) 안에서 다시 집는다(실행당 1건). 그 뒤에는 kept 상태로 남고 더 재시도되지
  # 않으므로, STALE_RETRY_AGE를 넘긴 기사는 오분류일 수 있어 종료 시각과 함께 error로 남긴다.
  #: (Article article, Symbol reason) -> Dry::Monads::Result
  def keep_for_retry(article, reason)
    message = "Keeping article #{article.id} (#{article.url}) for retry: #{reason}"
    created_at = article.created_at
    if created_at < STALE_RETRY_AGE.ago
      logger.error "#{message}; retries stop after #{(created_at + ArticleBatchJob::LOOKBACK).iso8601}"
    else
      logger.warn message
    end
    Failure(reason)
  end

  #: (Article article, Symbol reason) -> Dry::Monads::Result
  def discard_with(article, reason)
    logger.warn "Discarding article #{article.id} (#{article.url}): #{reason}"
    article.discard!
    Failure(reason)
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

  # 에이전트 호출·응답 해석의 예외만 rescue한다. 결과 처리(else)의 예외는 저장 뒤 로깅 등에서
  # 날 수 있어, 반영된 윤문을 실패로 덮어쓰지 않도록 여기서 잡지 않는다.
  #: (Article article) -> Dry::Monads::Result
  def run_humanize(article)
    message = HumanMonolithAgent.chat.with_skills.ask(ArticleHumanizer.prompt(article))
    content = Articles::AgentResponse.structured(message)
    extraction = ArticleHumanizer.extract(content)
  rescue StandardError => e
    fail_humanize(article, e, stage: :agent, message: "Failed to humanize article #{article.id}")
  else
    case extraction
    when ArticleHumanizer::Skipped then skip_humanize(article, extraction, content)
    when ArticleHumanizer::Humanized then apply_humanized(article, extraction, content)
    else
      # extract에 새 결과 타입이 생기면 Sorbet이 이 분기를 정적 오류로 잡는다.
      T.absurd(extraction)
    end
  end

  #: (Article article, ArticleHumanizer::Humanized humanized, Hash[String, untyped] content) -> Dry::Monads::Result
  def apply_humanized(article, humanized, content)
    result = save_humanized(article, humanized)
    return result if result.failure?

    log_dropped_fields(article, humanized)
    logger.info "Humanize metrics for article #{article.id}: #{content['metrics']}"
    result
  end

  # 윤문 필드와 결과(humanize_status)를 같은 update!로 저장한다. 저장하지 못한 값이 메모리에
  # 남으면 이후 단계(무관 기사 정리의 discard!)가 함께 저장할 수 있으므로 되돌린다.
  #
  # update!는 커밋 뒤 after_commit 콜백(RSS 캐시·IndexNow)의 예외도 다시 던진다. 그때는 이미
  # 저장됐으므로 실패로 기록하지 않는다. 롤백이 dirty 추적을 되돌려 dirty로는 구분할 수 없어,
  # 명시적 트랜잭션 안에서 update!가 끝났는지(saved)와 DB에 실제로 커밋됐는지(committed?)로 구분한다.
  #: (Article article, ArticleHumanizer::Humanized humanized) -> Dry::Monads::Result
  def save_humanized(article, humanized)
    attributes = humanized.to_attributes.merge(humanize_status: ArticleHumanizer.status(humanized))
    saved = false #: bool
    begin
      Article.transaction do
        article.update!(attributes)
        saved = true
      end
    rescue StandardError => e
      return post_commit_failure(article, e) if saved && committed?(article, attributes[:humanize_status])

      article.restore_attributes(attributes.keys)
      return fail_humanize(article, e, stage: :save, message: "Failed to save humanized article #{article.id}")
    end
    Success(article)
  end

  # saved는 COMMIT 전에 켜진다. COMMIT 자체가 실패할 수도 있으므로(직렬화 실패·연결 오류) 이번에
  # 쓴 humanize_status가 DB에 실제로 있는지 다시 읽어 확인한다. 읽지 못하면 커밋되지 않은 것으로 본다.
  #: (Article article, Hash[String, untyped] status) -> bool
  def committed?(article, status)
    Article.where(id: article.id).pick(:humanize_status) == status
  rescue ActiveRecord::ActiveRecordError
    false
  end

  #: (Article article, StandardError error) -> Dry::Monads::Result
  def post_commit_failure(article, error)
    logger.error "Humanized article #{article.id} was saved but an after commit callback failed: " \
                 "#{error.class}: #{error.message}", { article_id: article.id, error: error.class.name }
    Success(article)
  end

  # 본문만 반영되고 요점·상세는 원 요약 값으로 남은 경우. 원 요약에 그 필드가 원래 없었을 수도
  # 있어 계약 위반으로 단정하지 않고 info로 남긴다. 조회는 humanize_partially_applied로 한다.
  #: (Article article, ArticleHumanizer::Humanized humanized) -> void
  def log_dropped_fields(article, humanized)
    dropped = humanized.dropped_keys
    return if dropped.empty?

    logger.info "Humanize partially applied for article #{article.id}: kept existing #{dropped.join(', ')}",
                { article_id: article.id, dropped: }
  end

  # 기록을 먼저 해서 로깅이 실패해도 상태는 남긴다.
  #: (Article article, StandardError error, stage: Symbol, message: String) -> Dry::Monads::Result
  def fail_humanize(article, error, stage:, message:)
    record_humanize_status(article, ArticleHumanizer.failed_status(error, stage:))
    logger.error "#{message}: #{error.class}: #{error.message}",
                 { article_id: article.id, stage: stage.to_s, error: error.class.name }
    Failure(ArticleHumanizer::FAILED_REASON.to_sym)
  end

  # 건너뜀·실패 기록은 다른 속성 변경 없이 컬럼만 쓴다(update_column). 저장 실패로 메모리에 남은
  # 다른 변경을 함께 저장하지 않고, 검증과 콜백(RSS 캐시·IndexNow)도 건너뛴다. DB 오류로 기록하지
  # 못해도 윤문 결과(Failure)는 그대로 돌려주도록 로그만 남긴다.
  #: (Article article, Hash[String, untyped] status) -> void
  def record_humanize_status(article, status)
    article.update_column(:humanize_status, status)
  rescue ActiveRecord::ActiveRecordError => e
    logger.error "Failed to record humanize status for article #{article.id}: #{e.class}: #{e.message}",
                 { article_id: article.id, status: }, e
  end

  # call은 윤문 실패를 무시하고 진행하므로, 건너뛴 사유를 로그와 humanize_status에 남긴다.
  # 과윤문 롤백은 모델의 정상 판단이라 info, 응답이 계약을 어긴 경우는 warn이다.
  # 응답 클래스를 함께 남겨 JSON이 아닌 응답(String)과 형식이 틀린 Hash를 구분한다.
  #: (Article article, ArticleHumanizer::Skipped skipped, untyped content) -> Dry::Monads::Result
  def skip_humanize(article, skipped, content)
    record_humanize_status(article, ArticleHumanizer.status(skipped))
    message = "Humanize skipped for article #{article.id}: #{skipped.reason} (response #{content.class})"
    payload = { article_id: article.id, reason: skipped.reason, response_class: content.class.name }
    skipped.aborted? ? logger.info(message, payload) : logger.warn(message, payload)
    Failure(skipped.reason)
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
