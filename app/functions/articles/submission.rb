# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

module Articles
  # 사용자가 등록 폼으로 제출한 기사의 저장과 중복 판정.
  module Submission
    extend FunctionLogger

    # db/schema.rb의 유니크 인덱스 이름과 일치해야 한다.
    URL_INDEXES = %w[index_articles_on_url index_articles_on_origin_url].freeze
    SLUG_INDEX = "index_articles_on_slug"

    class << self
      # 저장 결과를 :created, :discarded, :duplicate, :invalid 중 하나로 돌려준다. rescue를 저장에만 걸어,
      # 저장 이후 단계(like!·job)의 예외를 "이미 등록된 기사"로 오인하지 않게 한다.
      #: (Article article, user_id: Integer) -> Symbol
      def save_submitted(article, user_id:)
        outcome = save_with_slug_retry(article)
        return article.discarded? ? :discarded : :created if outcome == :saved
        return :duplicate if outcome == :duplicate || (article.duplicate_url? && only_url_conflicts?(article))

        :invalid
      rescue ActiveRecord::RecordNotUnique => e
        constraint = violated_constraint(e)
        # fedipub 콜백 등 기사 URL/slug와 무관한 위반은 사용자 중복 안내로 숨기지 않는다.
        logger.error "Article submission unique violation user=#{user_id} constraint=#{constraint.inspect} " \
                     "url=#{safe_log_url(article.url.to_s).inspect} " \
                     "error=#{e.class} cause=#{e.cause&.class} detail=#{safe_error_detail(e).inspect}"
        raise unless URL_INDEXES.include?(constraint) || constraint == SLUG_INDEX

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
      # 이 경우만 접미사를 붙여 한 번 다시 저장한다. 준비된 메타데이터를 재사용하며,
      # 재충돌은 save_submitted가 제약 이름으로 분류한다.
      #: (Article article) -> Symbol
      def save_with_slug_retry(article)
        article.save ? :saved : :invalid
      rescue ActiveRecord::RecordNotUnique => e
        raise unless violated_constraint(e) == SLUG_INDEX

        article.slug = "#{article.slug}-#{SecureRandom.hex(4)}"
        return :saved if article.save

        # 준비된 URL이 재검증에서 충돌하면 INSERT 위반과 같은 안내로 처리한다.
        only_url_conflicts?(article) ? :duplicate : :invalid
      end

      #: (Article article) -> bool
      def only_url_conflicts?(article)
        article.errors.any? && article.errors.all? do |error|
          %i[url origin_url].include?(error.attribute) && error.type == :taken
        end
      end

      #: (String url) -> String
      def safe_log_url(url)
        parsed = URI.parse(url)
        return "[invalid URL]" unless parsed.is_a?(URI::HTTP)

        parsed.user = nil
        parsed.password = nil
        parsed.query = nil
        parsed.fragment = nil
        parsed.to_s
      rescue URI::InvalidURIError
        "[invalid URL]"
      end

      # SQL/PG 오류 맥락은 남기되 키 값과 URL은 제거한다. inspect로 개행 로그 위조도 막는다.
      #: (ActiveRecord::RecordNotUnique error) -> String
      def safe_error_detail(error)
        error.message.gsub(/Key \((.*?)\)=\(.*\)(?= already exists\.)/m, 'Key (\1)=(FILTERED)')
             .gsub(%r{https?://[^\s'"]+}, "[FILTERED_URL]")
      end

      #: (ActiveRecord::RecordNotUnique error) -> String?
      def violated_constraint(error)
        cause = error.cause
        cause.result&.error_field(PG::Constants::PG_DIAG_CONSTRAINT_NAME) if cause.is_a?(PG::UniqueViolation)
      end
    end
  end
end
