# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

# Rails 내장 `rate_limit`의 `by:`·`with:` 처리기. 한도는 각 컨트롤러가 회원 단위로 선언한다.
# 예: rate_limit to: 20, within: 1.hour, by: :rate_limit_key, with: :handle_rate_limit, only: :create
module RateLimiting
  extend ActiveSupport::Concern

  private

  # IP는 Cloudflare 엣지 주소라 여러 회원이 한도를 나눠 쓰게 되므로 회원 ID로 센다.
  #: () -> Integer
  def rate_limit_key
    current_user.id
  end

  #: () -> void
  def handle_rate_limit
    render_rate_limit_error unless current_user&.admin?
  end

  #: () -> void
  def render_rate_limit_error
    if request.format.symbol == :html
      redirect_back fallback_location: root_path, alert: I18n.t("posts.rate_limit_exceeded")
    else
      render json: { error: "Rate limit exceeded" }, status: :too_many_requests
    end
  end
end
