# typed: true
# frozen_string_literal: true

class Views::Home::Index < Views::Base
  include Phlex::Rails::Helpers::ContentFor
  include Phlex::Rails::Helpers::LinkTo

  def initialize(articles:, recent_comments:, sidebar_tags:, recent_blog_posts: [], liked_article_ids: [], boosted_article_ids: [], featured_articles: [])
    @articles = articles
    @featured_articles = featured_articles
    @recent_comments = recent_comments
    @recent_blog_posts = recent_blog_posts
    @sidebar_tags = sidebar_tags
    @liked_article_ids = liked_article_ids
    @boosted_article_ids = boosted_article_ids
  end

  def view_template
    content_for :title, t("home.index.title")

    render_item_list_schema

    div(class: "flex flex-col lg:flex-row gap-6") do
      div(class: "flex-1 min-w-0") do
        h1(class: "sr-only") { t("home.index.heading") }

        if @featured_articles.any?
          render Components::Home::Feature.new(
            articles: @featured_articles,
            liked_article_ids: @liked_article_ids,
            boosted_article_ids: @boosted_article_ids
          )
        end

        div(class: "lg:hidden mb-6 space-y-6") do
          render_activity_sidebars(limit: 1)
        end

        section do
          div(class: "flex items-center mb-4") do
            h2(class: "text-2xl font-bold text-content") { t("home.index.latest_news") }
          end

          div(id: "articlesList", class: "grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6") do
            @articles.each do |article|
              render Components::Home::Article.new(article: article, liked: @liked_article_ids.include?(article.id), boosted: @boosted_article_ids.include?(article.id))
            end
          end
        end

        if @articles.any?
          div(class: "mt-8 flex justify-center") do
            link_to(
              articles_path,
              class: "inline-flex items-center gap-1 px-5 py-2.5 rounded-md border border-border-strong bg-surface text-content hover:bg-surface-muted hover:text-link-hover transition-colors duration-200 text-sm font-medium"
            ) do
              plain t("home.index.more_articles")
              span(class: "ml-1") { "→" }
            end
          end
        end
      end

      div(class: "hidden lg:block w-72 shrink-0 space-y-6") do
        render_activity_sidebars
        render Components::TagsSidebar.new(tags: @sidebar_tags)
      end
    end
  end

  private

  # to_a로 relation을 한 번만 로드해 모바일·데스크톱 블록이 같은 결과를 나눠 쓴다.
  def render_activity_sidebars(limit: nil)
    posts = @recent_blog_posts.to_a
    comments = @recent_comments.to_a
    render Components::RecentBlogPostsSidebar.new(posts: limit ? posts.first(limit) : posts)
    render Components::RecentCommentsSidebar.new(recent_comments: limit ? comments.first(limit) : comments)
  end

  def render_item_list_schema
    render Components::StructuredData::ItemList.new(
      name: t("home.index.item_list_name"),
      articles: @featured_articles + @articles
    )
  end
end
