# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

class RssSitePageJob < ApplicationJob
  include RssHelper
  include LinkHelper

  def self.enqueue_all
    RssSitePageJob.perform_later(Site.kept.rss_page.order("id ASC").pluck(:id))
  end

  #: (Array[Integer] | Integer ids) -> void
  def perform(ids)
    ids = [ ids ] unless ids.is_a?(Array)
    site_id = ids.shift
    return if site_id.nil?

    site = Site.find_by(id: site_id)
    if site.nil?
      # 예약 후 삭제된 사이트 하나 때문에 뒤의 사이트 수집까지 끊기지 않도록 건너뛴다.
      logger.warn "site #{site_id} not found, skipping RssSitePageJob"
      RssSitePageJob.perform_later(ids) unless ids.empty?
      return
    end

    Rss::PageCrawler.crawl(site)

    logger.info "site #{site.id} RssSitePageJob finished"
    site.update!(last_checked_at: Time.zone.now)
    RssSitePageJob.perform_later(ids) unless ids.empty?
  end
end
