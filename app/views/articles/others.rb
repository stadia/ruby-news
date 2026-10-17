# typed: true
# frozen_string_literal: true

class Views::Articles::Others < Views::Base
  include Phlex::Rails::Helpers::ContentFor

  def initialize(pagy:, articles:, sidebar_tags:, recent_blog_posts: [], search: nil, liked_article_ids: [], boosted_article_ids: [])
    @pagy = pagy
    @articles = articles
    @sidebar_tags = sidebar_tags
    @recent_blog_posts = recent_blog_posts
    @search = search
    @liked_article_ids = liked_article_ids
    @boosted_article_ids = boosted_article_ids
  end

  def view_template
    content_for :title, t("articles.others.title")

    render_item_list_schema

    div(class: "flex flex-col lg:flex-row gap-6") do
      div(class: "flex-1 min-w-0") do
        div(class: "mb-8") do
          render RubyUI::Heading.new(level: 1, class: "font-bold text-content mb-4") { t("articles.others.heading") }
          p(class: "text-lg text-content-secondary") do
            plain t("articles.others.count", count: @pagy.count)
            plain " #{@search}" if @search.present?
          end
        end

        div(class: "lg:hidden mb-6") do
          render Components::TagsSidebar.new(tags: @sidebar_tags)
        end

        div(id: "articlesList", class: "space-y-6 lg:space-y-8") do
          @articles.each do |article|
            render Components::Articles::Article.new(article: article, liked: @liked_article_ids.include?(article.id), boosted: @boosted_article_ids.include?(article.id))
          end

          render Components::Pagination.new(pagy: @pagy)
        end
      end

      div(class: "w-full lg:w-72 shrink-0 order-last lg:order-0 space-y-6") do
        render Components::RecentBlogPostsSidebar.new(posts: @recent_blog_posts)
        div(class: "hidden lg:block") do
          render Components::TagsSidebar.new(tags: @sidebar_tags)
        end
      end
    end
  end

  private

  def render_item_list_schema
    render Components::StructuredData::ItemList.new(
      name: t("articles.others.item_list_name"),
      articles: @articles
    )
  end
end
