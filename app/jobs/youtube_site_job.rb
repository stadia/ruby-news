# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

class YoutubeSiteJob < ApplicationJob
  # YouTube URL의 정규화된 호스트를 상수로 정의
  YOUTUBE_NORMALIZED_HOST = "www.youtube.com".freeze

  def self.enqueue_all
    YoutubeSiteJob.perform_later(Site.kept.youtube.order("id ASC").pluck(:id))
  end

  # perform은 큐에서 역직렬화된 인자를 받는 지점이라 시그니처가 런타임을 강제하지 못한다.
  # 단일 id로 enqueue되는 경로(콘솔, 재시도 중인 구버전 잡)도 받아들이도록 배열로 승격한다.
  #: ((Array[Integer] | Integer) ids) -> void
  def perform(ids)
    ids = [ ids ] unless ids.is_a?(Array)
    site_id = ids.shift
    return if site_id.nil?

    site = Site.find_by(id: site_id)
    if site.nil?
      # 예약 후 삭제된 사이트 하나 때문에 뒤의 사이트 수집까지 끊기지 않도록 건너뛴다.
      logger.warn "site #{site_id} not found, skipping YoutubeSiteJob"
      YoutubeSiteJob.perform_later(ids) unless ids.empty?
      return
    end

    client = site.init_client
    return unless client.is_a?(Youtube::Channel)

    videos = client.videos
    return if videos.nil?

    last_checked = site.last_checked_at
    videos.each do |video|
      break if last_checked && last_checked > video.published_at

      # 정규화된 URL 사용
      url = "https://#{YOUTUBE_NORMALIZED_HOST}/watch?v=#{video.id}"
      Article.create(url: url, origin_url: url, title: video.title, published_at: video.published_at, site:, user: User.find_by(username: "bot")) unless Article.exists?(origin_url: url)
      sleep 1
    end

    site.update(last_checked_at: Time.zone.now)
    YoutubeSiteJob.perform_later(ids) unless ids.empty?
  rescue Yt::Errors::RequestError => e
    raise unless youtube_quota_exceeded?(e)

    logger.warn("YoutubeSiteJob stopped because YouTube API quota was exceeded: #{e.message}")
  end

  private

  #: (Yt::Errors::RequestError error) -> bool
  def youtube_quota_exceeded?(error)
    response_error = error.response_body.fetch("error", {})

    response_error["code"] == 429 ||
      response_error["status"] == "RESOURCE_EXHAUSTED" ||
      error.reasons.include?("rateLimitExceeded")
  end
end
