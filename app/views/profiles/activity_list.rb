# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

class Views::Profiles::ActivityList < Views::Base
  include Phlex::Rails::Helpers::ContentFor
  include Phlex::Rails::Helpers::TurboFrameTag

  # Maps an activity tab to its empty-state i18n key.
  # Explicit hash: tab names (posts, comments) are plural but the i18n keys are
  # singular (post_list, comment_list), so a naive "#{tab}_list" interpolation
  # would miss them. blog matches by coincidence — don't rely on that.
  EMPTY_KEYS = {
    posts: "profiles.post_list.empty",
    comments: "profiles.comment_list.empty",
    blog: "profiles.blog_list.empty"
  }.freeze

  #: (user: User, posts: Array[Post] | ActiveRecord::Relation, pagy: Pagy, active_tab: Symbol, ?liked_post_ids: Array[Integer], ?boosted_post_ids: Array[Integer], ?embedded: bool) -> void
  def initialize(user:, posts:, pagy:, active_tab:,
                 liked_post_ids: [], boosted_post_ids: [], embedded: false)
    @user = user
    @posts = posts
    @pagy = pagy
    @active_tab = active_tab
    @empty_key = EMPTY_KEYS.fetch(active_tab)
    @liked_post_ids = liked_post_ids
    @boosted_post_ids = boosted_post_ids
    @embedded = embedded
  end

  def view_template
    if @embedded
      list_content
    else
      # rubocop:disable I18n/RailsI18n/DecorateStringFormattingUsingInterpolation dynamic tab scope
      content_for :title, "@#{@user.username} — #{t("profiles.activity_tabs.#{@active_tab}")}"
      # rubocop:enable I18n/RailsI18n/DecorateStringFormattingUsingInterpolation
      div(class: "max-w-2xl mx-auto py-10 px-4 sm:px-6") do
        turbo_frame_tag("activity-list", class: "block") do
          render Components::Profiles::ActivityTabs.new(user: @user, active_tab: @active_tab)
          div(class: "mt-4") { list_content }
        end
      end
    end
  end

  private

  def list_content
    if @posts.empty?
      div(class: "text-center py-16 text-content-muted") do
        p { t(@empty_key) }
      end
    else
      div(class: "flex flex-col gap-4") do
        div(class: "flex flex-col gap-3") do
          @posts.each do |post|
            render Components::Posts::PostCard.new(
              post: post,
              liked: @liked_post_ids.include?(post.id),
              boosted: @boosted_post_ids.include?(post.id)
            )
          end
        end
        render Components::Pagination.new(pagy: @pagy)
      end
    end
  end
end
