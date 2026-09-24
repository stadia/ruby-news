# typed: true
# rbs_inline: enabled

module Madmin
  class ArticlesController < Madmin::ResourceController
    def discard
      if @record.discard
        redirect_to madmin_article_path(@record), notice: "기사를 폐기했습니다."
      else
        redirect_to madmin_articles_path, alert: "기사 폐기에 실패했습니다."
      end
    rescue StandardError => e
      redirect_to madmin_articles_path, alert: "오류가 발생했습니다: #{e.message}"
    end

    def restore
      if @record.undiscard
        redirect_to madmin_article_path(@record), notice: "기사를 복원했습니다."
      else
        redirect_to madmin_articles_path, alert: "기사 복원에 실패했습니다."
      end
    rescue StandardError => e
      redirect_to madmin_articles_path, alert: "오류가 발생했습니다: #{e.message}"
    end

    def mark_unrelated
      if @record.update(is_related: false)
        redirect_to madmin_article_path(@record), notice: "기사를 관련 없음으로 표시했습니다."
      else
        redirect_to madmin_article_path(@record), alert: "관련 없음 표시에 실했습니다: #{@record.errors.full_messages.join(", ")}"
      end
    rescue StandardError => e
      redirect_to madmin_article_path(@record), alert: "오류가 발생했습니다: #{e.message}"
    end

    def reprocess
      if @record.discarded?
        redirect_to madmin_article_path(@record), alert: "폐기된 기사는 재처리할 수 없습니다."
      else
        logger.info "Re-processing article #{@record.id}"
        ArticleJob.perform_later(@record.id)
        redirect_to madmin_article_path(@record), notice: "재처리를 요청했습니다. 완료까지 몇 분 걸릴 수 있습니다."
      end
    rescue StandardError => e
      redirect_to madmin_article_path(@record), alert: "오류가 발생했습니다: #{e.message}"
    end

    def regenerate_thumbnail
      if @record.discarded?
        redirect_to madmin_article_path(@record), alert: "폐기된 기사는 썸네일을 재생성할 수 없습니다."
      else
        logger.info "Regenerating thumbnail for article #{@record.id}"
        ArticleThumbnailJob.perform_later(@record.id, force: true)
        redirect_to madmin_article_path(@record), notice: "썸네일 재생성을 요청했습니다. 완료까지 몇 분 걸릴 수 있습니다."
      end
    rescue StandardError => e
      redirect_to madmin_article_path(@record), alert: "오류가 발생했습니다: #{e.message}"
    end

    def translate_japanese
      if @record.discarded?
        redirect_to madmin_article_path(@record), alert: "폐기된 기사는 일본어 번역을 할 수 없습니다."
      else
        logger.info "Re-translating article #{@record.id} to Japanese"
        ArticleJapaneseJob.perform_later(@record.id)
        redirect_to madmin_article_path(@record), notice: "일본어 재번역을 요청했습니다. 완료까지 몇 분 걸릴 수 있습니다."
      end
    rescue StandardError => e
      redirect_to madmin_article_path(@record), alert: "오류가 발생했습니다: #{e.message}"
    end

    private

    # Override: full_text_search_for 스코프(tsvector + bigm 인덱스)로
    # Madmin 기본 LOWER(CAST(...)) LIKE 전체 스캔 검색을 대체한다.
    # 기본 검색은 body, summary_body 같은 TOAST 컬럼까지 포함해 416ms+ 소요.
    def scoped_resources
      resources = resource.model.send(valid_scope)
      resources = if search_term.present?
                    resources.full_text_search_for(search_term).without_toast
      else
                    resources
      end
      resources.includes(:site).reorder(sort_column => sort_direction)
    end

    def resource_params
      hash = super
      hash[:user_id] = User.first_bot.id
      hash
    end
  end
end
