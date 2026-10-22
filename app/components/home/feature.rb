# typed: true
# frozen_string_literal: true

class Components::Home::Feature < Components::Base
  include Phlex::Rails::Helpers::DOMID
  include Phlex::Rails::Helpers::LinkTo
  include Phlex::Rails::Helpers::ImageTag
  include PhlexIcons

  def initialize(articles:, liked_article_ids: [], boosted_article_ids: [])
    @articles = articles
    @liked_article_ids = liked_article_ids
    @boosted_article_ids = boosted_article_ids
  end

  def view_template
    return if @articles.empty?

    hero, *rest = @articles

    section(class: "mb-8") do
      div(class: "flex items-center mb-4") do
        h2(class: "text-2xl font-bold text-content") { t("home.feature.heading") }
      end

      div(class: "grid grid-cols-1 lg:grid-cols-3 gap-6") do
        div(class: "lg:col-span-2") { hero_card(hero) }

        if rest.any?
          div(class: "grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-1 gap-6") do
            rest.each { |article| small_card(article) }
          end
        end
      end
    end
  end

  private

  def hero_card(article)
    render RubyUI::Card.new(
      id: dom_id(article, :feature),
      class: "relative bg-surface border-border-muted hover:border-border-strong hover:shadow-md transition-all duration-300 overflow-hidden flex flex-col h-full"
    ) do
      thumbnail(article, variant: :hero, aspect: "aspect-video", eager: true, responsive: true)
      div(class: "p-6 flex flex-col flex-1") do
        title_block(article, size: :large)
        render RubyUI::Badge.new(variant: :blue, size: :sm, class: "mb-4 self-start") { article.host }
        summary_block(article) if article.display_summary_key.present?
        meta_block(article)
      end
    end
  end

  def small_card(article)
    render RubyUI::Card.new(
      id: dom_id(article, :feature),
      class: "relative bg-surface border-border-muted hover:border-border-strong hover:shadow-sm transition-all duration-300 overflow-hidden flex flex-col h-full"
    ) do
      thumbnail(article, variant: :card, aspect: "aspect-video")
      div(class: "p-4 flex flex-col flex-1") do
        title_block(article, size: :small)
        render RubyUI::Badge.new(variant: :blue, size: :sm, class: "mb-3 self-start") { article.host }
        meta_block(article)
      end
    end
  end

  def thumbnail(article, variant:, aspect:, eager: false, responsive: false)
    return unless article.thumbnail.attached?

    thumbnail_url = cdn_variant_url(article.thumbnail, variant)

    attrs = {
      class: "w-full #{aspect} object-cover",
      loading: eager ? "eager" : "lazy",
      decoding: eager ? "auto" : "async",
      fetchpriority: eager ? "high" : "auto",
      alt: article.display_title
    }
    # 히어로는 반응형 srcset으로 모바일에 작은 변형(600px)을 제공해 LCP 바이트를 줄인다.
    if responsive
      card_url = (variant == :card) ? thumbnail_url : cdn_variant_url(article.thumbnail, :card)
      hero_url = (variant == :hero) ? thumbnail_url : cdn_variant_url(article.thumbnail, :hero)
      attrs[:srcset] = "#{card_url} 600w, #{hero_url} 1200w"
      attrs[:sizes] = "(min-width: 1024px) 66vw, 100vw"
    end

    link_to(article_path(article), class: "block overflow-hidden relative z-10", data: { turbo_prefetch: false }) do
      image_tag(thumbnail_url, **attrs)
    end
  end

  def title_block(article, size:)
    heading_class = size == :large ? "text-2xl font-bold mb-2 leading-tight" : "text-lg font-bold mb-2 leading-snug"

    div(class: "mb-3") do
      h3(class: "#{heading_class} text-content hover:text-link-hover transition-colors duration-200") do
        link_to(article.display_title, article_path(article), class: "after:absolute after:inset-0 after:content-['']", data: { turbo_prefetch: false })
      end
      if size == :large
        p(class: "text-base text-content-secondary wrap-break-word") { article.title }
      end
    end
  end

  def summary_block(article)
    summary = article.display_summary_key
    div(class: "text-content-secondary mb-4 text-base leading-relaxed grow space-y-2") do
      case summary
      when Array
        ul(class: "list-disc pl-5 space-y-1") do
          summary.first(3).each { |item| li { span(class: "line-clamp-2") { item } } }
        end
      when String
        p(class: "line-clamp-3") { summary }
      end
    end
  end

  def meta_block(article)
    render RubyUI::Separator.new(class: "mt-auto")
    div(class: "relative z-10 pt-3 flex flex-wrap justify-between items-center text-sm text-content-secondary gap-y-2") do
      span(class: "inline-flex items-center") do
        Hero::User(variant: :outline, class: "w-4 h-4 mr-1 text-content-muted")
        render Components::Articles::ArticleUser.new(article: article)
      end
      render Components::Likes::Button.new(likeable: article, liked: @liked_article_ids.include?(article.id))
      render Components::Boosts::Button.new(boostable: article, boosted: @boosted_article_ids.include?(article.id))
      span(class: "inline-flex items-center") do
        Hero::ChatBubbleLeftEllipsis(variant: :outline, class: "w-4 h-4 mr-1 text-content-muted")
        plain article.posts_count.to_s
      end
    end
  end
end
