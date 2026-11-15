# typed: true
# frozen_string_literal: true

class Components::Home::EpisodeSources < Components::Base
  def initialize(article:)
    @article = article
  end

  def view_template
    urls = ::Articles::HomeEpisodes.source_urls(@article)
    return if urls.empty?

    div(class: "relative z-10 flex flex-wrap gap-1 mb-4") do
      urls.zip(%w[announcement podcast video]).each do |url, kind|
        label = t(kind, scope: "home.episode_sources")
        render RubyUI::Link.new(
          href: url, variant: :link, size: :sm, class: "min-h-11",
          aria: { label: t("home.episode_sources.link_label", source: label, title: @article.display_title) }
        ) do
          plain label
        end
      end
    end
  end
end
