# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

# 같은 On Rails 에피소드를 다른 출처로 수집한 기사에 공통 episode_key를 붙인다(Articles::OnRailsEpisode).
# 영상이 팟캐스트 피드보다 먼저 올라오기도 해서, 수집 시 한 번이 아니라 최근 기사를 주기적으로 다시 본다.
class ArticleEpisodeLinkJob < ApplicationJob
  queue_as :default

  # 정기 실행은 최근 2일만 본다. 배포 전에 수집된 기사는 perform_now(30)처럼 기간을 늘려 한 번 돌린다.
  #: (?Integer lookback_days) -> void
  def perform(lookback_days = 2)
    feed = nil #: String?
    candidates(lookback_days.days.ago).find_each do |article|
      key = Articles::OnRailsEpisode.key_for(article, -> { feed ||= Articles::OnRailsEpisode.fetch_feed })
      next if key.nil?

      article.update_column(:episode_key, key)
      logger.info "Linked article #{article.id} to episode #{key}"
    rescue Faraday::Error, SafeHttp::BlockedUrlError, Yt::Error => e
      logger.warn "Episode link skipped for article #{article.id}: #{e.class}: #{e.message}"
    end
  end

  private

  #: (ActiveSupport::TimeWithZone since) -> ActiveRecord::Relation
  def candidates(since)
    Article.kept.without_toast.where(episode_key: nil, created_at: since..)
           .where("url LIKE 'https://podcast.rubyonrails.org/%' OR url LIKE 'https://rubyonrails.org/%/on-rails-%' OR is_youtube")
  end
end
