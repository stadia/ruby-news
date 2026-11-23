# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

class RssSiteJob < ApplicationJob
  include RssHelper

  def self.enqueue_all
    RssSiteJob.perform_later(Site.kept.rss.order("id ASC").pluck(:id))
  end

  # Performs the job for a given site ID.
  #: (Array[Integer] | Integer ids) -> void
  def perform(ids)
    # ids는 Active Job의 arguments와 같은 객체라 shift로 바꾸면 재시도에서 현재 사이트가 빠진다.
    site_id, *ids = Array(ids)
    site = Site.kept.find_by(id: site_id)
    if site.nil?
      RssSiteJob.perform_later(ids) unless ids.empty?
      return
    end

    begin
      feed = fetch_feed(site)
      return unless feed # 다음 잡 예약은 ensure가 한다

      create_articles_from_feed(feed, site)

      site.update!(last_checked_at: Time.zone.now)
    rescue Faraday::ForbiddenError, Faraday::UnauthorizedError => e
      logger.warn("Site #{site.id} (#{site.name}) discarded: #{e.class} - #{e.message}")
      site.discard!
    rescue Faraday::TooManyRequestsError => e
      logger.warn("Site #{site.id} (#{site.name}) rate limited, skipping: #{e.message}")
    rescue StandardError => e
      logger.error("Site #{site.id} (#{site.name}) failed: #{e.class} - #{e.message}")
    ensure
      RssSiteJob.perform_later(ids) unless ids.empty?
    end
  end

  private

  def create_articles_from_feed(feed, site)
    new_articles = new_articles_from_feed(feed, site)
    new_articles.each do |article_attrs|
      create_article(article_attrs.merge(site: site))
    end
  end

  # Extracts new article attributes from the feed, ready for creation.
  def new_articles_from_feed(feed, site)
    attributes = feed_items(feed).map { |item| extract_item_attributes(item) }.compact

    if site.last_checked_at
      attributes.reject! { |attr| attr[:published_at] < site.last_checked_at }
    end
    return [] if attributes.empty?

    logger.debug attributes
    existing_urls = Article.where(origin_url: attributes.pluck(:origin_url)).pluck(:origin_url)
    attributes.reject! { |attr| existing_urls.include?(attr[:origin_url]) }
    attributes
  end
end
