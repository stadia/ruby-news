# typed: true
# frozen_string_literal: true

class Components::Posts::PostCard < Components::Base
  include Phlex::Rails::Helpers::DOMID
  include Phlex::Rails::Helpers::LinkTo
  include Phlex::Rails::Helpers::Sanitize
  include PhlexIcons

  def initialize(post:, depth: 0, liked: nil, boosted: nil, booster: nil, show_actions: true, show_reply_badge: true)
    @post = post
    @depth = depth
    @liked = liked
    @boosted = boosted
    @booster = booster
    @show_actions = show_actions
    @show_reply_badge = show_reply_badge
  end

  def view_template
    div(
      id: dom_id(@post),
      class: wrapper_classes,
      data: {
        controller: "feed-reply",
        feed_reply_parent_id_value: @post.id,
        feed_reply_author_name_value: author_name,
        feed_reply_body_preview_value: body_preview
      }
    ) do
      render RubyUI::Card.new(class: "bg-surface border-border-muted shadow-sm hover:border-border-strong transition-all duration-200") do
        render RubyUI::CardContent.new(class: "p-4 sm:p-5 space-y-3") do
          post_header
          post_body
          post_actions if @show_actions
        end
      end
    end
  end

  private

  def wrapper_classes
    classes = []
    if @depth.positive?
      classes << "ml-4 sm:ml-8 border-l-2 border-border-muted pl-3 sm:pl-4"
    end
    classes.join(" ")
  end

  def post_header
    boost_attribution if @booster.present?
    parent_reply_badge if @show_reply_badge && @post.parent.present?

    div(class: "flex items-center gap-3") do
      render Components::UserAvatar.new(
        user: @post.user,
        fedipub_actor: @post.fedipub_actor,
        name: author_name,
        size: "h-8 w-8 sm:h-10 sm:w-10"
      )

      div(class: "flex-1 min-w-0") do
        span(class: "font-semibold text-content text-sm") { author_name }
        # PostCard renders inside the profile "activity-list" turbo frame, so
        # navigations to a full show page must break out with turbo_frame: "_top"
        # (otherwise the frame is replaced with "Content missing"). In non-frame
        # contexts like the feed this is just a normal full-page navigation.
        link_to(post_permalink_path(@post), class: "block text-xs text-content-muted hover:text-content transition-colors", data: { turbo_frame: "_top" }) do
          time(
            datetime: @post.created_at.iso8601,
            title: I18n.l(@post.created_at, format: :long)
          ) do
            plain view_context.time_ago_in_words(@post.created_at)
          end
        end
      end
    end
  end

  def parent_reply_badge
    render RubyUI::Badge.new(
      variant: :secondary,
      size: :sm,
      class: "mb-2 inline-flex items-center gap-1.5"
    ) do
      Hero::ArrowUturnLeft(variant: :outline, class: "w-3 h-3")
      plain t("posts.post_card.reply_to", name: parent_author_name)
    end
  end

  def boost_attribution
    div(class: "flex items-center gap-1.5 text-xs text-content-muted mb-2") do
      Hero::ArrowsRightLeft(variant: :outline, class: "w-3 h-3")
      plain t("posts.post_card.boosted_by", name: booster_name)
    end
  end

  def post_body
    if @post.blog?
      blog_body
    else
      short_body
    end

    post_tags if post_tag_names.any?
    media_attachments if @post.media_attachments.any?
    article_preview if @post.article.present?
  end

  def short_body
    div(class: "post-content text-content leading-relaxed wrap-break-word prose prose-sm dark:prose-invert max-w-none") do
      raw sanitize(@post.body.to_s, tags: HtmlSanitizable::ALLOWED_TAGS)
    end
  end

  def blog_body
    div(class: "space-y-2") do
      h2(class: "text-xl font-semibold text-content") do
        link_to @post.title, post_permalink_path(@post), class: "hover:text-accent-text transition-colors", data: { turbo_frame: "_top" }
      end
      p(class: "text-sm leading-relaxed text-content-secondary wrap-break-word") do
        plain @post.blog_summary
      end
      link_to t("posts.blog.read_more"), post_permalink_path(@post), class: "text-sm font-medium text-accent-text hover:underline", data: { turbo_frame: "_top" }
    end
  end

  def post_tags
    div(class: "flex flex-wrap gap-1 mt-1") do
      post_tag_names.each do |tag|
        span(class: "text-xs text-link hover:text-link-hover hover:underline cursor-pointer transition-colors") { plain "##{tag}" }
      end
    end
  end

  def post_tag_names
    @post_tag_names ||= @post.tags.map(&:name)
  end

  def media_attachments
    attachments = @post.media_attachments.select { |a| a["url"].present? }
    return if attachments.empty?

    grid_class = attachments.size == 1 ? "grid-cols-1" : "grid-cols-2"
    div(
      data: { controller: "lightbox", lightbox_stylesheet: helpers.asset_path("vendor/lightgallery.css") },
      class: "grid #{grid_class} gap-1 rounded-xl overflow-hidden mt-2"
    ) do
      attachments.each do |attachment|
        a(href: attachment["url"], data: { sub_html: attachment["name"].presence }) do
          img(
            src: attachment["url"],
            alt: attachment["name"].to_s,
            class: "w-full object-cover max-h-72 bg-surface-muted hover:opacity-90 transition-opacity cursor-pointer",
            loading: "lazy"
          )
        end
      end
    end
  end

  def post_actions
    div(class: "flex items-center gap-4 text-sm text-content-muted") do
      render Components::Likes::Button.new(likeable: @post, liked: @liked)

      render Components::Boosts::Button.new(boostable: @post, boosted: @boosted)

      render RubyUI::Button.new(
        variant: :ghost,
        size: :sm,
        data: { action: "feed-reply#activate" },
        class: "inline-flex items-center gap-1 text-content-muted hover:text-info-text transition-colors hover:bg-transparent p-0"
      ) do
        Hero::ChatBubbleLeft(variant: :outline, class: "w-4 h-4")
        if @post.children_count.positive?
          span { @post.children_count.to_s }
        end
      end
    end
  end

  def article_preview
    article = @post.article

    render RubyUI::Card.new(class: "bg-surface-muted border-border-muted shadow-none overflow-hidden") do
      render RubyUI::CardContent.new(class: "p-4 space-y-3") do
        div(class: "flex items-center gap-2 text-xs text-content-muted") do
          Hero::Newspaper(variant: :outline, class: "w-4 h-4")
          plain t("posts.post_card.linked_article")
        end

        div(class: "space-y-1") do
          h3(class: "text-sm font-semibold text-content leading-snug") do
            link_to(article.display_title.presence || t("posts.post_card.view_article"), article_path(article), class: "hover:text-link-hover", data: { turbo_frame: "_top", turbo_prefetch: false })
          end

          p(class: "text-xs text-content-secondary wrap-break-word") { article.title }
        end

        if article.summary_key_preview.present?
          p(class: "text-sm text-content-secondary leading-relaxed") { article.summary_key_preview }
        end

        div(class: "flex flex-wrap items-center gap-3 text-xs text-content-muted") do
          if article.host.present?
            span(class: "inline-flex items-center gap-1") do
              Hero::GlobeAlt(variant: :outline, class: "w-3 h-3")
              plain article.host
            end
          end

          if article.published_at.present?
            span(class: "inline-flex items-center gap-1") do
              Hero::CalendarDays(variant: :outline, class: "w-3 h-3")
              plain I18n.l(article.published_at, format: :short)
            end
          end
        end
      end
    end
  end

  def author_name
    @post.user&.name || @post.fedipub_actor&.name || t("posts.post_card.unknown_author")
  end

  def booster_name
    @booster&.name.presence || t("posts.post_card.unknown_author")
  end

  def parent_author_name
    @post.parent.user&.name || @post.parent.fedipub_actor&.name || t("posts.post_card.unknown_author")
  end

  def body_preview
    view_context.truncate(view_context.strip_tags(@post.body.to_s).squish, length: 120)
  end
end
