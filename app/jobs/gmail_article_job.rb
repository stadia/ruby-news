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
    ids = [ ids ] unless ids.is_a?(Array)
    site_id = ids.shift
    return if site_id.nil?

    site = Site.find(site_id)
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
    article = Article.create_with(url: link, site: site, user: User.find_by(username: "bot"))
                     .find_or_create_by!(origin_url: link)

    if article.previously_new_record?
      logger.info "Created article for #{link}"
      sleep 1
    end
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => e
    logger.error "Failed to create article for #{link}: #{e.message}"
  rescue ActiveRecord::RecordNotUnique => e
    logger.error "Article already exists for #{link}: #{e.message}"
  end
end
