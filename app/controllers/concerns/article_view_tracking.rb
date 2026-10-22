# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

module ArticleViewTracking
  extend ActiveSupport::Concern

  included do
    after_action :track_article_view, only: :show
  end

  private

  def track_article_view
    return unless request.get? && response.media_type == "text/html" && response.successful?
    return if %w[X-Sec-Purpose Sec-Purpose Purpose].any? { |header| request.headers[header].to_s.include?("prefetch") }
    return if ahoy.exclude?

    ahoy.track "Viewed article", article_id: @article.id
    set_ahoy_cookies
  end
end
