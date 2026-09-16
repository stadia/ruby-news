# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

# head 안에서 서로 떨어진 위치에 렌더되는 자산 프리로드 관련 마크업을 한 곳에 모은다.
# head 요소 순서(성능·CSP 민감)를 보존하기 위해 각 섹션은 원래 위치에서
# `section:` 인자로 개별 렌더된다.
class Components::Layout::AssetPreloads < Components::Base
  def initialize(section:)
    @section = section
  end

  def view_template
    case @section
    when :preconnect then render_asset_preconnect
    when :pwa_and_icons then render_pwa_and_icons
    when :google_fonts then render_google_fonts
    end
  end

  private

  def render_pwa_and_icons
    link(rel: "manifest", href: pwa_manifest_path(format: :json))
    link(rel: "apple-touch-icon", sizes: "180x180", href: "/apple-touch-icon.png")
    link(rel: "icon", type: "image/png", sizes: "32x32", href: "/favicon-32x32.png")
    link(rel: "icon", type: "image/png", sizes: "16x16", href: "/favicon-16x16.png")
  end

  # asset_host(예: assets.ruby-news.dev)는 cross-origin이라, 렌더 차단
  # app.css와 preload되는 코어 JS 모듈의 첫 요청 전에 DNS+TLS 연결을 예열한다.
  # asset_host 설정(람다 또는 문자열)을 그대로 사용해 호스트 판별 로직(단일 진실원)을
  # 재사용한다. ruby-news.jp(same-origin)나 개발환경(asset_host nil)에서는 아무것도
  # 렌더하지 않는다.
  def render_asset_preconnect
    # 이미지 CDN(cdn.ruby-news.dev): LCP 히어로 썸네일이 여기서 직접 서빙되므로
    # 가장 먼저 연결을 예열한다(<img>는 비-CORS라 crossorigin 없이).
    image_cdn = ENV["ACTIVE_STORAGE_CDN_HOST"].presence
    link(rel: "preconnect", href: image_cdn.delete_suffix("/")) if image_cdn

    origin = asset_preconnect_origin
    return if origin.blank?

    # asset_host는 CSS/이미지(비-CORS)와 ES 모듈(CORS)을 모두 서빙하므로
    # 두 연결 풀을 각각 예열한다(fonts.googleapis/gstatic 패턴과 동일).
    link(rel: "preconnect", href: origin)
    link(rel: "preconnect", href: origin, crossorigin: true)
  rescue StandardError => e
    # preconnect는 성능 최적화일 뿐이라 페이지 렌더는 계속하되,
    # "no silent failures" 원칙에 따라 삼키지 않고 신호를 남긴다.
    Rails.logger.error("render_asset_preconnect failed: #{e.class} - #{e.message}")
    nil
  end

  # asset_host 설정을 그대로 해석해 preconnect 대상 origin을 반환한다(단일 진실원).
  # 람다(request 기반)와 문자열 설정을 모두 지원하고, 미설정(dev)이면 nil.
  #: (?untyped request) -> String?
  def asset_preconnect_origin(request = view_context.request)
    host = ActionController::Base.asset_host
    host.respond_to?(:call) ? host.call(nil, request) : host
  end

  def render_google_fonts
    href = "https://fonts.googleapis.com/css2?family=Noto+Sans+KR:wght@400;500;700&display=swap"
    link(rel: "preconnect", href: "https://fonts.googleapis.com")
    link(rel: "preconnect", href: "https://fonts.gstatic.com", crossorigin: true)
    # 폰트 CSS를 렌더 차단에서 제외한다: preload로 받아온 뒤 onload에서 rel을
    # stylesheet로 전환하고, display=swap으로 로드 중 텍스트가 숨지 않게 한다.
    # Phlex는 onload 인라인 핸들러를 막으므로 정적 문자열을 raw로 렌더한다.
    raw(%(<link rel="preload" href="#{CGI.escapeHTML(href)}" as="style" onload="this.onload=null;this.rel='stylesheet'">).html_safe)
    noscript { link(rel: "stylesheet", href: href) }
  end
end
