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
    # ids는 Active Job의 arguments와 같은 객체라 shift로 바꾸면 재시도에서 현재 사이트가 빠진다.
    site_id, *ids = Array(ids)
    return if site_id.nil?

    site = Site.find_by(id: site_id)
    if site
      crawl(site)
    else
      logger.warn "site #{site_id} not found, skipping YoutubeSiteJob"
    end

    # crawl이 정상 반환하면(조회 실패로 건너뛴 경우 포함) 다음 사이트로 이어간다.
    # 예외가 나면 이어가지 않는다. 쿼터 초과는 아래 rescue에서 삼키고, 그 밖의 예외는 전파된다.
    YoutubeSiteJob.perform_later(ids) unless ids.empty?
  rescue Yt::Errors::RequestError => e
    raise unless youtube_quota_exceeded?(e)

    logger.warn("YoutubeSiteJob stopped because YouTube API quota was exceeded: #{e.message}")
  end

  private

  # 조회하지 못한 사이트는 last_checked_at을 갱신하지 않아 다음 실행에서 놓친 영상을 다시 본다.
  #: (Site site) -> void
  def crawl(site)
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
  end

  #: (Yt::Errors::RequestError error) -> bool
  def youtube_quota_exceeded?(error)
    response_error = error.response_body.fetch("error", {})

    response_error["code"] == 429 ||
      response_error["status"] == "RESOURCE_EXHAUSTED" ||
      error.reasons.include?("rateLimitExceeded")
  end
end
