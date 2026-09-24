# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

# admin에서 요청한 기사 일본어 재번역. DeepL 실패 시 LLM 폴백까지 갈 수 있어 요청 중에 돌리지 않는다.
class ArticleJapaneseJob < ApplicationJob
  queue_as :default

  #: (Integer id) -> void
  def perform(id)
    article = Article.kept.find_by(id: id)

    unless article.is_a?(Article)
      logger.info "ArticleJapaneseJob skip: article #{id} not found or discarded"
      return
    end

    result = ArticleJapaneseService.new.call(article)
    logger.warn "ArticleJapaneseJob failed for article #{id}: #{result.failure}" if result.failure?
  end
end
