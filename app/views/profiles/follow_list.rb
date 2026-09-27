# typed: true
# frozen_string_literal: true

class Views::Profiles::FollowList < Views::Base
  include Phlex::Rails::Helpers::ContentFor
  include Phlex::Rails::Helpers::LinkTo
  include Phlex::Rails::Helpers::TurboFrameTag
  include Phlex::Rails::Helpers::ButtonTo
  include PhlexIcons

  def initialize(user:, followings:, type:, embedded: false)
    @user = user
    @followings = followings
    @type = type
    @embedded = embedded
  end

  def view_template
    title = @type == :followers ? t("profiles.follow_list.followers") : t("profiles.follow_list.following")

    if @embedded
      list_content(title)
    else
      content_for :title, "@#{@user.username} — #{title}"
      div(class: "max-w-2xl mx-auto py-10 px-4 sm:px-6") do
        turbo_frame_tag("activity-list", class: "block") do
          render Components::Profiles::ActivityTabs.new(user: @user, active_tab: @type)
          div(class: "mt-4") { list_content(title) }
        end
      end
    end
  end

  private

  def list_content(title)
    if @followings.empty?
      div(class: "text-center py-16 text-content-muted") do
        p { @type == :followers ? t("profiles.follow_list.empty_followers") : t("profiles.follow_list.empty_following") }
      end
    else
      div(class: "flex flex-col gap-2") do
        @followings.each { |following| following_row(following) }
      end
    end
  end

  def following_row(following)
    actor = @type == :followers ? following.actor : following.target_actor

    site_host = URI.parse(Fedipub.configuration.site_host).host
    is_local = actor.server.blank? || actor.server == site_host
    handle = is_local ? "@#{actor.username}" : "@#{actor.username}@#{actor.server}"

    div(id: "following_row_#{following.id}", class: "flex items-center gap-4 px-4 py-3 bg-app/40 border border-border-subtle rounded-xl hover:border-border-strong transition-colors") do
      render RubyUI::Avatar.new(size: :md, class: "h-10 w-10 shrink-0") do
        icon_url = avatar_url_for(actor)
        if icon_url
          render RubyUI::AvatarImage.new(src: icon_url, alt: actor.name.presence || actor.username)
        else
          render RubyUI::AvatarFallback.new(class: "bg-brand-solid text-brand-foreground font-bold") do
            plain (actor.name.presence || actor.username).first.upcase
          end
        end
      end

      div(class: "flex-1 min-w-0") do
        if is_local && (local_user = actor.entity)
          a(href: "/@#{local_user.username}", class: "text-content font-semibold hover:text-link-hover transition-colors block truncate") do
            plain actor.name.presence || actor.username
          end
        else
          p(class: "text-content font-semibold truncate") { actor.name.presence || actor.username }
        end
        p(class: "text-content-muted text-sm font-mono truncate") { handle }
      end

      action_buttons(following) if own_profile?
    end
  end

  def action_buttons(following)
    div(class: "flex items-center gap-2 shrink-0") do
      if @type == :followers
        if following.pending?
          button_to t("profiles.follow_list.accept"), accept_following_path(following),
            method: :put,
            form: { data: { turbo_stream: true } },
            class: "px-3 py-1 text-xs font-medium bg-brand-solid hover:bg-brand-solid-hover text-brand-foreground rounded-lg transition-colors cursor-pointer"
          button_to t("profiles.follow_list.reject"), following_path(following),
            method: :delete,
            form: { data: { turbo_stream: true } },
            class: "px-3 py-1 text-xs font-medium bg-surface-muted hover:bg-surface text-content-secondary rounded-lg transition-colors cursor-pointer"
        end
      else
        if following.pending?
          follow_status_badge(t("profiles.follow_list.requested"), variant: :amber)
        else
          follow_status_badge(t("profiles.follow_list.following"), variant: :green)
        end
        button_to t("profiles.follow_list.unfollow"), following_path(following),
          method: :delete,
          form: { data: { turbo_stream: true } },
          class: "px-3 py-1 text-xs font-medium bg-surface-muted hover:bg-danger-solid text-content-secondary hover:text-danger-text rounded-lg transition-colors cursor-pointer"
      end
    end
  end

  def own_profile?
    view_context.current_user && view_context.current_user == @user
  end

  def follow_status_badge(text, variant:)
    render RubyUI::Badge.new(
      variant: variant,
      class: "inline-flex items-center rounded-lg px-3 py-1 text-xs font-medium"
    ) { text }
  end

  def avatar_url_for(actor)
    return actor.entity.avatar_url if actor.local? && actor.entity.respond_to?(:avatar_url) && actor.entity.avatar_attached?

    actor.extensions&.dig("icon", "url")
  end
end
