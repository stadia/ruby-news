# typed: true
# frozen_string_literal: true

class Components::Layout::MetaTags < Components::Base
  include Phlex::Rails::Helpers::ContentFor
  include Phlex::Rails::Helpers::ImageURL

  OG_LOCALES = {
    ko: "ko_KR",
    ja: "ja_JP",
    en: "en_US"
  }.freeze

  def view_template
    render_meta_tags
    render_rss_link
  end

  private

  def render_meta_tags
    # user-scalable=no / maximum-scale는 저시력 사용자의 확대를 막아 접근성(WCAG 1.4.4)을
    # 위반하므로 두지 않는다. 사용자가 핀치 줌으로 확대할 수 있어야 한다.
    meta(name: "viewport", content: "width=device-width,initial-scale=1,viewport-fit=cover")
    meta(name: "apple-mobile-web-app-capable", content: "yes")
    meta(name: "mobile-web-app-capable", content: "yes")
    meta(name: "apple-mobile-web-app-status-bar-style", content: "black-translucent")
    meta(name: "slack-app-id", content: "A0AS9BX8B7U")

    vc = view_context
    assigns = vc.assigns
    path = vc.request.path
    base = vc.request.base_url
    current_url = "#{base}#{path}"

    # 현재 로케일 번역이 없어 원문(한국어)으로 폴백된 페이지는 색인 제외.
    meta(name: "robots", content: "noindex, follow") if assigns["robots_noindex"]

    vc.set_meta_tags canonical: current_url
    page_title = content_for(:title).presence || vc.t("layout.default_title")
    page_desc = assigns["page_description"] || vc.t("layout.default_description")
    og_image = assigns["og_image"] || image_url("og_main_#{rand(2)}.png")
    og_locale = OG_LOCALES.fetch(I18n.locale, "ko_KR")

    raw vc.display_meta_tags(
      title: page_title,
      description: page_desc,
      og: {
        title: page_title,
        description: page_desc,
        site_name: vc.t("layout.site_name"),
        image: og_image,
        type: assigns["og_type"] || "website",
        url: current_url,
        locale: og_locale
      },
      article: assigns["og_article"],
      twitter: {
        card: "summary_large_image",
        site: "@rubynewskr",
        title: page_title,
        description: page_desc,
        image: og_image
      }
    )
  end

  def render_rss_link
    link(
      rel: "alternate",
      type: "application/rss+xml",
      title: t("layout.rss_feed_title"),
      href: "/rss"
    )
  end
end
