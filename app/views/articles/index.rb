# typed: true
# frozen_string_literal: true

class Views::Articles::Index < Views::Base
  include Phlex::Rails::Helpers::ContentFor

  def initialize(pagy: nil, articles: [], sidebar_tags: [], recent_blog_posts: [], search: nil, source: :ruby_news, liked_article_ids: [], boosted_article_ids: [], suggestions: [])
    @pagy = pagy
    @articles = articles
    @sidebar_tags = sidebar_tags
    @recent_blog_posts = recent_blog_posts
    @search = search
    @source = source
    @liked_article_ids = liked_article_ids
    @boosted_article_ids = boosted_article_ids
    @suggestions = suggestions
  end

  def view_template
    content_for :title, t("articles.index.title")

    render_item_list_schema unless google?

    render RubyUI::Heading.new(level: 1, class: "mb-4 font-bold text-content") { t("articles.index.heading") }
    render Components::Articles::SearchTabs.new(source: @source, search: @search) if searching?

    if google?
      render Components::Articles::GoogleSearch.new(query: @search)
    else
      render_ruby_news_results
    end
  end

  private

  def render_ruby_news_results
    div(class: "flex flex-col gap-6 lg:flex-row") do
      div(class: "min-w-0 flex-1") do
        p(class: "mb-8 text-lg text-content-secondary") do
          plain t("articles.index.count", count: @pagy.count)
          plain " #{@search}" if @search.present?
        end

        div(class: "mb-6 lg:hidden") do
          render Components::TagsSidebar.new(tags: @sidebar_tags)
        end

        div(id: "articlesList", class: "space-y-6 lg:space-y-8") do
          if @articles.empty? && @suggestions.any?
            div(class: "rounded-lg border border-border p-6") do
              p(class: "text-content-secondary mb-3") { t("articles.index.no_results") }
              p(class: "text-sm text-content-secondary") do
                plain t("articles.index.try_searching")
                @suggestions.each do |suggestion|
                  render Components::Articles::SearchSuggestion.new(query: suggestion)
                end
              end
            end
          end

          @articles.each do |article|
            render Components::Articles::Article.new(
              article: article,
              liked: @liked_article_ids.include?(article.id),
              boosted: @boosted_article_ids.include?(article.id)
            )
          end

          render Components::Pagination.new(pagy: @pagy)
        end
      end

      div(class: "w-full lg:w-72 shrink-0 order-last lg:order-0 hidden lg:block space-y-6") do
        render Components::RecentBlogPostsSidebar.new(posts: @recent_blog_posts)
        render Components::TagsSidebar.new(tags: @sidebar_tags)
      end
    end
  end

  def google?
    @source == :google
  end

  def searching?
    @search.present?
  end

  def render_item_list_schema
    render Components::StructuredData::ItemList.new(
      name: t("articles.index.item_list_name"),
      articles: @articles
    )
  end
end
