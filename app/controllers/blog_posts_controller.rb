# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

class BlogPostsController < ApplicationController
  include WebOnlyFormats

  # create·update는 초안 자동저장 JSON을 정식 제공한다.
  AUTOSAVE_JSON_ACTIONS = %w[create update].freeze

  before_action :authenticate_user!
  before_action :set_post, only: [ :edit, :update, :publish, :destroy, :undiscard, :destroy_permanently ]
  before_action :authorize_owner!, only: [ :edit, :update, :publish, :destroy, :undiscard, :destroy_permanently ]

  def index
    render Views::BlogPosts::Index.new(
      drafts: current_user.posts.blog.draft.kept.order(updated_at: :desc),
      published: current_user.posts.blog.published.kept.order(published_at: :desc),
      trash: current_user.posts.blog.discarded.order(updated_at: :desc)
    )
  end

  # Opens the editor for an unsaved draft (no row until the first autosave via
  # #create). The composer POSTs the body so it stays out of the URL; we stash it
  # in the cache under a per-request nonce, then redirect to the GET editor, which
  # carries the body over once. The nonce rides the redirect query — no session.
  def new
    if request.post?
      draft_key = SecureRandom.hex(8)
      body = params.dig(:post, :body).to_s
      # SolidCache returns false (not raise) on a failed write; redirect without
      # the nonce and alert rather than hand the editor a dead key.
      unless Rails.cache.write(blog_draft_cache_key(draft_key), body, expires_in: 1.week)
        logger.warn("[BlogPosts#new] draft stash write failed for user=#{current_user.id}")
        flash[:alert] = t("posts.blog.draft_stash_failed")
        return redirect_to new_blog_post_path, status: :see_other
      end
      return redirect_to new_blog_post_path(draft_key: draft_key), status: :see_other
    end

    @post = current_user.posts.new(
      post_type: :blog,
      status: :draft,
      body: carried_over_draft_body
    )
    render Views::BlogPosts::Edit.new(post: @post)
  end

  def create
    @post = current_user.posts.new(blog_post_params)
    @post.post_type = :blog

    if publishing?
      @post.publish!
      redirect_to user_profile_blog_post_path(username: @post.user.username, slug: @post), notice: t("posts.blog.published")
    else
      @post.status = :draft
      @post.title = I18n.t("posts.blog.untitled_draft") if @post.title.blank?
      respond_to do |format|
        if @post.save
          format.json { render json: created_draft_payload }
          format.html { redirect_to edit_blog_post_path(@post) }
        else
          format.json { render json: { errors: @post.errors.full_messages }, status: :unprocessable_entity }
          format.html { render Views::BlogPosts::Edit.new(post: @post), status: :unprocessable_entity }
        end
      end
    end
  rescue ActiveRecord::RecordInvalid
    render Views::BlogPosts::Edit.new(post: @post), status: :unprocessable_entity
  end

  def edit
    render Views::BlogPosts::Edit.new(post: @post)
  end

  def update
    if @post.update(blog_post_params)
      respond_to do |format|
        format.html { redirect_to user_profile_blog_post_path(username: @post.user.username, slug: @post), notice: t("posts.blog.updated") }
        format.json { render json: { status: "ok", saved_at: l(Time.current, format: :short) } }
      end
    else
      respond_to do |format|
        format.html { render Views::BlogPosts::Edit.new(post: @post), status: :unprocessable_entity }
        format.json { render json: { errors: @post.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def publish
    @post.assign_attributes(blog_post_params) if params[:post].present?
    @post.publish!
    redirect_to user_profile_blog_post_path(username: @post.user.username, slug: @post), notice: t("posts.blog.published")
  rescue ActiveRecord::RecordInvalid
    render Views::BlogPosts::Edit.new(post: @post), status: :unprocessable_entity
  end

  def destroy
    # Soft-delete via Discard::Model keeps the record so federation/tombstone
    # lookups still resolve. The model's `after_discard` callback emits an
    # ActivityPub Delete for published posts; drafts never federated.
    @post.discard
    redirect_to feed_path, notice: t("posts.blog.deleted")
  end

  def undiscard
    # Restoring a published post re-federates via the model's after_undiscard
    # (Undo); drafts were never federated, so nothing is emitted for them.
    @post.undiscard
    redirect_to account_blog_path, notice: t("posts.blog.restored")
  end

  def destroy_permanently
    # Hard-destroy removes the row for good. Fedipub' after_destroy emits a
    # Delete for a published post; since trash items were already soft-discarded
    # (which emitted a Delete too), remotes may receive a duplicate Delete. That
    # is benign — the tombstone already exists remotely, so the second Delete is
    # idempotent.
    @post.destroy
    redirect_to account_blog_path, notice: t("posts.blog.destroyed_permanently")
  end

  private

  # Reads and consumes the body stashed by the composer's POST. No nonce opens a
  # fresh editor; a nonce with no stash (expired/consumed/failed write) surfaces
  # a notice instead of silently dropping the in-progress body. Consumption is
  # best-effort — concurrent GETs may both read before deleting, but that only
  # duplicates a user's own body into their own tabs.
  def carried_over_draft_body
    draft_key = params[:draft_key]
    return "" if draft_key.blank?

    key = blog_draft_cache_key(draft_key)
    body = Rails.cache.read(key)
    if body.nil?
      logger.warn("[BlogPosts#new] draft stash miss for user=#{current_user.id} key=#{draft_key}")
      flash.now[:notice] = t("posts.blog.draft_expired")
      return ""
    end

    Rails.cache.delete(key)
    body
  end

  # Namespaced under the current user so a stashed body is only ever readable by
  # the account that wrote it (defense in depth against nonce guessing).
  def blog_draft_cache_key(draft_key)
    "blog_draft:#{current_user.id}:#{draft_key}"
  end

  # The publish button on an unsaved draft submits to #create with a publish
  # flag (HTML), so the draft is created and published in one request.
  def publishing?
    params[:publish].present? && !request.format.json?
  end

  # Tells the editor's autosave controller how to address the now-persisted
  # draft: switch from POST #create to PATCH #update and target the publish
  # route, all without a page reload.
  def created_draft_payload
    {
      status: "ok",
      saved_at: l(Time.current, format: :short),
      save_url: blog_post_path(@post, format: :json),
      form_url: blog_post_path(@post),
      publish_url: publish_blog_post_path(@post)
    }
  end

  # Discard adds no default scope, so undiscard/destroy_permanently must reach
  # soft-deleted rows. Every other action operates on live content only, so
  # restrict those to kept rows to avoid editing/publishing a trashed post.
  def set_post
    scope = Post.blog
    scope = scope.kept unless %w[undiscard destroy_permanently].include?(action_name)
    @post = scope.find_by!(slug: BlogSlug.lookup_key(params[:id]))
  end

  # 가드를 끄는 대신 지원 포맷만 넓힌다. `skip_before_action`으로 껐다면
  # XML 등 나머지 미지원 포맷도 액션에 들어와 `@post.save`/`update`가 커밋된
  # 뒤에야 `respond_to`가 406을 냈다 — 클라이언트에는 실패인데 데이터는 바뀐다.
  #: () -> Array[Symbol]
  def supported_web_formats
    return super + %i[json] if AUTOSAVE_JSON_ACTIONS.include?(action_name)

    super
  end

  def authorize_owner!
    return if @post.user == current_user
    redirect_to feed_path, alert: t("posts.blog.forbidden")
  end

  def blog_post_params
    params.expect(post: [ :title, :body, :tag_list ])
  end
end
