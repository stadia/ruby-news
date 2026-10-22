# typed: true
# frozen_string_literal: true

class Components::Home::Article < Components::Base
  include Phlex::Rails::Helpers::DOMID
  include Phlex::Rails::Helpers::LinkTo
  include Phlex::Rails::Helpers::ImageTag
  include PhlexIcons

  attr_reader :article

  def initialize(article:, liked: nil, boosted: nil)
    @article = article
    @liked = liked
    @boosted = boosted
  end

  def view_template
    render RubyUI::Card.new(id: dom_id(article), class:
        "relative bg-surface border-border-muted hover:border-border-strong hover:shadow-md transition-all duration-300 overflow-hidden flex flex-col"
    ) do
      div(class: "p-6 flex flex-col flex-1") do
        header_section
        render RubyUI::Badge.new(variant: :blue, size: :sm, class: "mb-4 self-start") { article.host }
        summary_section
        footer_section
      end
    end
  end

  private

  def header_section
    div(class: "mb-4") do
      h3(class: "text-xl font-bold text-content mb-2 leading-tight hover:text-link-hover transition-colors duration-200") do
        link_to(article.display_title, article_path(article), class: "after:absolute after:inset-0 after:content-['']", data: { turbo_prefetch: false })
      end
      p(class: "text-lg font-medium text-content-secondary wrap-break-word") { article.title }
    end
  end

  def summary_section
    div(class: "text-content-secondary mb-6 text-base leading-relaxed grow space-y-2") do
      summary = article.display_summary_key
      if summary.present?
        if summary.is_a?(Array)
          ul(class: "list-disc pl-5 space-y-1") do
            summary.each do |item|
              li { item }
            end
          end
        elsif summary.is_a?(String)
          p { summary }
        end
      end
    end
  end

  def footer_section
    render RubyUI::Separator.new(class: "mt-auto")
    div(class: "relative z-10 pt-4 flex flex-wrap justify-between items-center text-sm text-content-secondary gap-y-2") do
      span(class: "inline-flex items-center") do
        Hero::User(variant: :outline, class: "w-4 h-4 mr-1 text-content-muted")
        render Components::Articles::ArticleUser.new(article: article)
      end
      render Components::Likes::Button.new(likeable: article, liked: @liked)
      render Components::Boosts::Button.new(boostable: article, boosted: @boosted)
      span(class: "inline-flex items-center") do
        Hero::ChatBubbleLeftEllipsis(variant: :outline, class: "w-4 h-4 mr-1 text-content-muted")
        plain article.posts_count.to_s
      end
    end
  end
end
