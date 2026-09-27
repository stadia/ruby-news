# typed: true
# frozen_string_literal: true

class Views::BlogPosts::Index < Views::Base
  include Phlex::Rails::Helpers::ContentFor
  include Phlex::Rails::Helpers::LinkTo
  include Phlex::Rails::Helpers::ButtonTo

  def initialize(drafts: [], published: [], trash: [])
    @drafts = drafts
    @published = published
    @trash = trash
  end

  def view_template
    content_for :title, t("posts.blog.manage_title")
    div(class: "max-w-2xl mx-auto py-10 px-4 sm:px-6") do
      div(class: "mb-6 px-1") do
        render RubyUI::Heading.new(level: 1, class: "text-2xl font-bold text-content tracking-tight") { t("posts.blog.manage_heading") }
      end
      div(class: "flex flex-col gap-8") do
        drafts_section
        published_section
        trash_section
      end
    end
  end

  private

  def drafts_section
    section(class: "flex flex-col gap-3") do
      h2(class: "text-sm font-semibold text-content") { t("profiles.blog_list.drafts_heading") }
      drafts = @drafts.to_a
      if drafts.empty?
        empty_state(t("profiles.blog_list.drafts_empty"))
      else
        div(class: "flex flex-col gap-2") { drafts.each { |d| draft_row(d) } }
      end
    end
  end

  def published_section
    section(class: "flex flex-col gap-3") do
      h2(class: "text-sm font-semibold text-content") { t("profiles.blog_list.published_heading") }
      published = @published.to_a
      if published.empty?
        empty_state(t("profiles.blog_list.published_empty"))
      else
        div(class: "flex flex-col gap-2") { published.each { |p| published_row(p) } }
      end
    end
  end

  def trash_section
    section(class: "flex flex-col gap-3") do
      h2(class: "text-sm font-semibold text-content") { t("profiles.blog_list.trash_heading") }
      trash = @trash.to_a
      if trash.empty?
        empty_state(t("profiles.blog_list.trash_empty"))
      else
        div(class: "flex flex-col gap-2") { trash.each { |p| trash_row(p) } }
      end
    end
  end

  def empty_state(message)
    div(class: "text-center py-8 text-content-muted") { p { message } }
  end

  def draft_row(draft)
    row do
      link_to(edit_blog_post_path(draft),
        class: "min-w-0 flex-1 truncate text-sm text-content hover:text-brand-text transition-colors",
        data: { turbo_prefetch: false }) do
        plain draft.title.presence || t("posts.blog.untitled_draft")
      end
      div(class: "flex items-center gap-2 shrink-0") do
        button_to t("posts.blog.delete"), blog_post_path(draft),
          method: :delete,
          form: { data: { turbo_confirm: t("posts.blog.delete_confirm") } },
          class: "text-xs font-medium text-content-muted hover:text-danger-text transition-colors cursor-pointer"
      end
    end
  end

  def published_row(post)
    row do
      link_to(post_permalink_path(post),
        class: "min-w-0 flex-1 truncate text-sm text-content hover:text-brand-text transition-colors") do
        plain post.title.presence || t("posts.blog.untitled_draft")
      end
      div(class: "flex items-center gap-2 shrink-0") do
        link_to t("posts.blog.edit"), edit_blog_post_path(post),
          class: "text-xs font-medium text-content-muted hover:text-content transition-colors",
          data: { turbo_prefetch: false }
        button_to t("posts.blog.delete"), blog_post_path(post),
          method: :delete,
          form: { data: { turbo_confirm: t("posts.blog.delete_confirm") } },
          class: "text-xs font-medium text-content-muted hover:text-danger-text transition-colors cursor-pointer"
      end
    end
  end

  def trash_row(post)
    row do
      span(class: "min-w-0 flex-1 truncate text-sm text-content") do
        plain post.title.presence || t("posts.blog.untitled_draft")
      end
      div(class: "flex items-center gap-2 shrink-0") do
        button_to t("posts.blog.restore"), undiscard_blog_post_path(post),
          method: :patch,
          class: "text-xs font-medium text-content-muted hover:text-content transition-colors cursor-pointer"
        button_to t("posts.blog.destroy_permanently"), destroy_permanently_blog_post_path(post),
          method: :delete,
          form: { data: { turbo_confirm: t("posts.blog.destroy_permanently_confirm") } },
          class: "text-xs font-medium text-content-muted hover:text-danger-text transition-colors cursor-pointer"
      end
    end
  end

  def row(&block)
    div(class: "flex items-center justify-between gap-3 rounded-md border border-border-muted bg-app/40 px-3 py-2", &block)
  end
end
