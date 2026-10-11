# typed: true
# frozen_string_literal: true

class Components::RecentBlogPostsSidebar < Components::Base
  include Phlex::Rails::Helpers::L
  include Phlex::Rails::Helpers::LinkTo
  include PhlexIcons

  def initialize(posts:)
    @posts = posts.to_a
  end

  def view_template
    return if @posts.empty?

    aside(class: "recent-blog-posts-sidebar") do
      h3(class: "text-lg font-semibold text-content mb-4 flex items-center gap-2") do
        Hero::PencilSquare(variant: :outline, class: "w-5 h-5 text-accent-text")
        plain t("recent_blog_posts_sidebar.heading")
      end

      div(class: "space-y-3") do
        @posts.each { post_card(it) }
      end
    end
  end

  private

  def post_card(post)
    render RubyUI::Card.new(class: "bg-surface p-3 border-border-strong hover:border-border-muted transition-colors rounded-lg") do
      link_to(user_profile_blog_path(username: post.user.username), class: "group flex items-center gap-2 mb-2 w-fit max-w-full") do
        div(aria_hidden: true) do
          render Components::UserAvatar.new(
            user: post.user,
            name: post.author_name,
            size: "h-7 w-7",
            fallback_class: "bg-surface text-accent-text ring-1 ring-inset ring-border-muted font-bold"
          )
        end
        span(class: "text-sm font-medium text-content-secondary group-hover:text-link-hover truncate transition-colors") { post.author_name }
      end

      link_to(post.title, post_permalink_path(post), class: "block text-sm font-medium text-content hover:text-link-hover line-clamp-2 mb-2 transition-colors")

      if post.published_at
        div(class: "flex items-center gap-1 text-xs text-content-muted") do
          Hero::Clock(variant: :outline, class: "w-3 h-3")
          time(datetime: post.published_at.iso8601) { l(post.published_at, format: :short) }
        end
      end
    end
  end
end
