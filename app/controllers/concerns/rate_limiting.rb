# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

module RateLimiting
  extend ActiveSupport::Concern

  private

  def check_rate_limit
    user = current_user if respond_to?(:current_user) && current_user

    return if user&.admin?

    cache_key = "rate_limit:#{request.remote_ip}:#{controller_name}"
    current_count = Rails.cache.read(cache_key) || 0

    if current_count >= rate_limit_threshold
      render_rate_limit_error
      return
    end

    Rails.cache.write(cache_key, current_count + 1, expires_in: 1.hour)
  end

  def render_rate_limit_error
    if request.format.symbol == :html
      redirect_back fallback_location: root_path, alert: I18n.t("posts.rate_limit_exceeded")
    else
      render json: { error: "Rate limit exceeded" }, status: :too_many_requests
    end
  end

  def rate_limit_threshold
    case controller_name
    when "comments"
      10 # 10 comments per hour
    when "articles"
      5  # 5 articles per hour
    else
      20 # Default limit
    end
  end
end
