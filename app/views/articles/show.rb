# typed: true
# frozen_string_literal: true

class Views::Articles::Show < Views::Base
  include Phlex::Rails::Helpers::ContentFor
  include Phlex::Rails::Helpers::DOMID

  def initialize(article:, presenter:, comments:, comment:, similar_articles:)
    @article = article
    @comments = comments
    @comment = comment
    @similar_articles = similar_articles
    @presenter = presenter
  end

  def view_template
    content_for(:title, @article.display_title)

    # NewsArticle + breadcrumbs JSON-LD are rendered into <head> by
    # Components::Layout::StructuredData, which reads @news_article / @breadcrumbs
    # (set in ArticlesController#show) from view_context. They are NOT available as
    # Phlex view ivars here, so do not reference them in this template.

    div(class: "space-y-6 lg:space-y-8 max-w-6xl mx-auto", id: dom_id(@article)) do
      render_article_main
      render Components::Articles::Show::SimilarArticles.new(articles: @similar_articles)
      render Components::Articles::Show::CommentsSection.new(
        article: @article,
        comments: @comments,
        comment: @comment
      )
    end
  end

  private

  def render_article_main
    article(class: "bg-surface rounded-xl overflow-hidden border border-border-strong") do
      render Components::Articles::Show::Header.new(presenter: @presenter)
      render RubyUI::Separator.new
      render Components::Articles::Show::Summary.new(presenter: @presenter)
    end
  end
end
