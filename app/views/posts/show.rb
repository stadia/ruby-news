# typed: true
# frozen_string_literal: true

class Views::Posts::Show < Views::Base
  include Phlex::Rails::Helpers::ContentFor
  include Phlex::Rails::Helpers::LinkTo
  include Phlex::Rails::Helpers::ButtonTo
  include Phlex::Rails::Helpers::Sanitize
  include PhlexIcons

  def initialize(posts:, liked_post_ids: [], boosted_post_ids: [])
    @posts = posts
    @liked_post_ids = liked_post_ids
    @boosted_post_ids = boosted_post_ids
  end

  def view_template
    content_for :title, page_title

    div(class: "#{container_width} mx-auto space-y-4") do
      back_link
      render_posts
    end
  end

  private

  # 블로그 글은 본문 가독폭을 넓게(896px) 잡고, 일반 포스트는 기존 폭을 유지한다.
  def container_width
    @posts.first&.blog? ? "max-w-4xl" : "max-w-2xl"
  end

  def page_title
    root = @posts.first
    return root.title if root&.blog? && root.title.present?

    t("posts.show.title")
  end

  def back_link
    div(class: "mb-2") do
      link_to feed_path, class: "inline-flex items-center gap-1.5 text-sm text-content-muted hover:text-content transition-colors" do
        Hero::ArrowLeft(variant: :outline, class: "w-4 h-4")
        plain t("posts.show.back_to_feed")
      end
    end
  end

  def render_posts
    root = @posts.first
    return unless root

    # 루트 포스트
    if root.blog?
      render_blog(root)
    else
      render Components::Posts::PostCard.new(
        post: root,
        liked: @liked_post_ids.include?(root.id),
        boosted: @boosted_post_ids.include?(root.id),
        show_reply_badge: false
      )
    end

    # 답글 영역
    replies = @posts[1..] || []
    div(id: "replies_#{root.id}", class: "space-y-4") do
      replies.sort_by(&:created_at).each do |reply|
        render Components::Posts::PostCard.new(
          post: reply,
          liked: @liked_post_ids.include?(reply.id),
          boosted: @boosted_post_ids.include?(reply.id),
          show_reply_badge: false
        )
      end
    end
  end

  def render_blog(root)
    article(class: "rounded-lg border border-border-muted bg-surface p-5 sm:p-8 space-y-5") do
      h1(class: "text-3xl font-bold text-content") { root.title }
      div(class: "text-sm text-content-muted") do
        plain I18n.l(root.published_at || root.created_at, format: :short)
      end
      # body is allowlist-sanitized on save (Posts::Blog#sanitize_body → BlogBody);
      # we sanitize again at render time with the same blog allowlist as defense
      # in depth. `sanitize` returns a SafeBuffer, so `raw` accepts it without an
      # explicit html_safe marker.
      div(class: "post-content prose prose-lg dark:prose-invert max-w-none text-content wrap-break-word") do
        raw sanitize(root.body.to_s, tags: BlogBody::ALLOWED_TAGS)
      end
      owner_controls(root)
    end
  end

  def owner_controls(root)
    return unless view_context.current_user == root.user

    div(class: "flex items-center gap-3 pt-4 border-t border-border-muted") do
      link_to t("posts.blog.edit"), edit_blog_post_path(root),
        class: "text-sm font-medium text-content-muted hover:text-content transition-colors",
        data: { turbo_prefetch: false }
      button_to t("posts.blog.delete"), blog_post_path(root),
        method: :delete,
        form: { data: { turbo_confirm: t("posts.blog.delete_confirm") } },
        class: "text-sm font-medium text-content-muted hover:text-danger-text transition-colors cursor-pointer"
    end
  end
end
