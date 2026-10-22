# typed: true
# frozen_string_literal: true

# 기사 상세 하단의 관련 기사 카드 그리드.
class Components::Articles::Show::SimilarArticles < Components::Base
  include PhlexIcons
  include Phlex::Rails::Helpers::LinkTo

  def initialize(articles:)
    @articles = articles
  end

  def view_template
    return if @articles.blank?

    render RubyUI::Card.new(class: "bg-surface overflow-hidden border-border-strong") do
      render RubyUI::CardContent.new(class: "p-4 md:p-6 lg:p-8") do
        render RubyUI::Heading.new(level: 2, class: "font-bold text-content mb-6 flex items-center") do
          Hero::Newspaper(variant: :outline, class: "w-6 h-6 mr-2 text-brand")
          plain t("articles.show.related_heading")
        end

        div(class: "grid grid-cols-1 md:grid-cols-2 gap-4 lg:gap-6") do
          @articles.each { |article| render_card(article) }
        end
      end
    end
  end

  private

  def render_card(article)
    div(class: "group bg-surface-muted rounded-lg border border-border-muted hover:border-border-strong hover:shadow-sm transition-all duration-200 overflow-hidden") do
      link_to(article_path(article), class: "block p-4 lg:p-6", data: { turbo_prefetch: false }) do
        render RubyUI::Heading.new(
          level: 3,
          class: "font-semibold text-content group-hover:text-link-hover transition-colors duration-200 mb-3 line-clamp-2"
        ) { article.display_title }

        render RubyUI::Badge.new(variant: :blue, size: :sm, class: "mb-3") { article.host }

        p(class: "text-content-secondary text-sm leading-relaxed line-clamp-3 mb-4") do
          plain article.summary_key_preview.to_s
        end

        div(class: "flex items-center justify-end text-xs text-content-secondary") do
          span(class: "group-hover:text-link-hover transition-colors duration-200") { t("articles.show.read_more") }
        end
      end
    end
  end
end
