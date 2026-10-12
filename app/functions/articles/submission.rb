# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

module Articles
  # 사용자가 등록 폼으로 제출한 기사의 저장과 중복 판정.
  module Submission
    extend FunctionLogger

    SLUG_INDEX = "index_articles_on_slug"

    class << self
      # 저장 결과를 :created, :duplicate, :invalid 중 하나로 돌려준다. rescue를 저장에만 걸어,
      # 저장 이후 단계(like!·job)의 예외를 "이미 등록된 기사"로 오인하지 않게 한다.
      #: (Article article, user_id: Integer) -> Symbol
      def save_submitted(article, user_id:)
        return :created if save_with_slug_retry(article)
        return :duplicate if article.duplicate_url?

        :invalid
      rescue ActiveRecord::RecordNotUnique => e
        # URL 정규화(utm 제거, 호스트 소문자화)는 검증 뒤 before_create에서 일어나므로,
        # 검증을 통과한 URL이 INSERT에서 기존 기사와 겹칠 수 있다.
        logger.warn "Article submission hit a unique index for user #{user_id} (#{article.url}): " \
                    "#{violated_constraint(e) || e.class}"
        :duplicate
      end

      # 제출한 기사와 겹친 기존 기사. url과 origin_url이 서로 다른 기사와 겹칠 수 있으므로
      # 살아 있는 기사를 먼저 고른다.
      #: (Article article) -> Article?
      def existing_for(article)
        candidates = Article.where(url: article.url).or(Article.where(origin_url: article.origin_url))
        candidates.kept.first || candidates.first
      end

      private

      # slug는 존재 확인 직후 INSERT하므로 그 사이에 같은 slug가 들어오면 유니크 인덱스에 걸린다.
      # 이 경우만 접미사를 붙여 한 번 다시 저장한다. 다시 걸리면 호출부가 중복으로 처리한다.
      #: (Article article) -> bool
      def save_with_slug_retry(article)
        article.save
      rescue ActiveRecord::RecordNotUnique => e
        raise unless violated_constraint(e) == SLUG_INDEX

        article.slug = "#{article.slug}-#{SecureRandom.hex(4)}"
        article.save
      end

      #: (ActiveRecord::RecordNotUnique error) -> String?
      def violated_constraint(error)
        cause = error.cause
        cause.result&.error_field(PG::Constants::PG_DIAG_CONSTRAINT_NAME) if cause.is_a?(PG::UniqueViolation)
      end
    end
  end
end
