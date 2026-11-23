# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

class GmailArticleJob < ApplicationJob
  include LinkHelper

  def self.enqueue_all
    GmailArticleJob.perform_later(Site.kept.gmail.order("id ASC").pluck(:id))
  end

  # Performs the job for a given site ID.
  #: (Array[Integer] | Integer ids) -> void
  def perform(ids)
    # ids는 Active Job의 arguments와 같은 객체라 shift로 바꾸면 재시도에서 현재 사이트가 빠진다.
    site_id, *ids = Array(ids)
    return if site_id.nil?

    site = Site.find_by(id: site_id)
    if site.nil?
      # 예약 후 삭제된 사이트 하나 때문에 뒤의 사이트 수집까지 끊기지 않도록 건너뛴다.
      logger.warn "site #{site_id} not found, skipping GmailArticleJob"
      GmailArticleJob.perform_later(ids) unless ids.empty?
      return
    end
    return if site.email.blank?

    links = fetch_new_email_links(site)
    if links.nil?
      # 클라이언트 초기화 실패: 조회가 수행되지 않았으므로 체크포인트를 갱신하지 않고 다음 사이트로 진행한다.
      logger.error "Gmail 클라이언트 초기화에 실패해 last_checked_at을 갱신하지 않습니다 (site_id=#{site.id})"
      GmailArticleJob.perform_later(ids) unless ids.empty?
      return
    end

    if links.empty?
      site.update!(last_checked_at: Time.zone.now)
      GmailArticleJob.perform_later(ids) unless ids.empty?
      return
    end

    create_articles_from_links(links, site)

    site.update!(last_checked_at: Time.zone.now)
    GmailArticleJob.perform_later(ids) unless ids.empty?
  end

  private

  # Fetches new email links from the site's email account.
  # Returns nil when the client cannot be initialized (no fetch was performed).
  #: (Site site) -> Array[String]?
  def fetch_new_email_links(site)
    client = site.init_client
    return unless client.is_a?(Gmail)

    client.fetch_email_links(from: site.email, since: (site.last_checked_at || 1.day.ago) - 1.day)
  end

  # Iterates over links and creates articles.
  #: (Array[String] links, Site site) -> void
  def create_articles_from_links(links, site)
    links.each do |link|
      processed_link = extract_link(link)
      next if processed_link.blank?

      logger.info "Processing link: #{processed_link}"
      next if Article.exists?(origin_url: processed_link)

      create_article(processed_link, site)
    end
  end

  # Creates an article for a given link.
  #: (String link, Site site) -> void
  def create_article(link, site)
    # 호출부가 origin_url 존재를 이미 확인했다. find_or_create_by!는 유니크 위반 시 origin_url로 다시 찾다가
    # 다른 기사와 겹친 url 경합에서 RecordNotFound로 잡을 폐기시키므로, 위반을 그대로 받아 아래에서 기록한다.
    Article.create!(origin_url: link, url: link, site: site, user: User.find_by(username: "bot"))
    logger.info "Created article for #{link}"
    sleep 1
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => e
    logger.error "Failed to create article for #{link}: #{e.message}"
  rescue ActiveRecord::RecordNotUnique => e
    logger.error "Article already exists for #{link}: #{e.message}"
  end
end
