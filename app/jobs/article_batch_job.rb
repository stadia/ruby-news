# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

class ArticleBatchJob < ApplicationJob
  include JobRateLimiting

  queue_as :default

  # 당일 처리하지 못한 기사(자정 직전 수집분, 일시 실패분)도 다시 집도록 며칠을 돌아본다.
  LOOKBACK = 3.days

  # `Time.zone.now` returns an ActiveSupport::TimeWithZone, which only quacks
  # like Time -- it is not a subclass -- so the default value does not satisfy
  # a bare `Time` annotation.
  #: (?(Time | ActiveSupport::TimeWithZone) created_at) -> void
  def perform(created_at = LOOKBACK.ago)
    Article.kept.where(title_ko: nil, created_at: created_at...).order(:updated_at).limit(5).each do |article|
      unless check_rate_limit
        logger.warn("ArticleBatchJob: rate limit reached, stopping batch early")
        break
      end

      begin
        ArticleAgentsService.new.call(article)
      rescue StandardError => e
        logger.error("Error processing article #{article.id}: #{e.message}")
      ensure
        # 실패한 기사가 다음 실행에서 다시 맨 앞에 잡히지 않도록 뒤로 보낸다.
        # touch는 after_commit(RSS 캐시·IndexNow)을 돌리므로 컬럼만 갱신한다.
        article.update_column(:updated_at, Time.current)
      end
      sleep 1
    end
  end

  private

  #: () -> Integer
  def rate_limit_threshold
    1
  end

  #: () -> ActiveSupport::Duration
  def rate_limit_window
    # 실행 주기(5분)와 같으면 직전 카운터가 만료 직전이라 한 번씩 건너뛴다.
    4.minutes
  end
end
