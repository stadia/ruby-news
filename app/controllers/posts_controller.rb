# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

class PostsController < ApplicationController
  include RateLimiting
  include PostViewing

  skip_before_action :authenticate_user!, only: [ :show ]
  before_action :authenticate_user!, only: [ :create, :destroy ]
  # 인증 뒤에 포맷을 본다. 위 `before_action`이 전역 `authenticate_user!`를
  # 다시 등록해 체인 끝으로 옮기므로, concern을 먼저 include하면 미인증 JSON
  # 요청이 401 대신 406을 받는다.
  include WebOnlyFormats
  before_action :set_article, only: [ :create, :destroy ], if: :article_scoped_request?
  before_action :set_post, only: [ :destroy ]
  before_action :check_rate_limit, only: [ :create ]

  def show
    post = Post.where.not(post_type: :blog).includes(POST_SHOW_INCLUDES).find_by!(slug: params[:id])
    render_post_show(post)
  end

  def create
    if @article
      create_article_comment
    else
      create_standalone_post
    end
  end

  def destroy
    if @post.user != current_user
      respond_to do |format|
        format.html { redirect_back fallback_location: root_path, alert: "권한이 없습니다." }
        format.turbo_stream { head :unauthorized }
      end
      return
    end

    @article = @post.article
    @post.destroy

    if @article
      load_article_comments
      respond_to do |format|
        format.html { redirect_to @article, notice: "댓글이 삭제되었습니다." }
        format.turbo_stream { render "posts/destroy_article_comment" }
      end
    else
      respond_to do |format|
        format.html { redirect_to feed_path, notice: "포스트가 삭제되었습니다." }
        format.turbo_stream
      end
    end
  end

  private

  def article_scoped_request?
    params[:article_id].present?
  end

  def create_article_comment
    @post = @article.posts.build(article_comment_params.merge(post_type: :comment, status: :published))
    @post.user = current_user
    @post.published_at ||= Time.zone.now

    respond_to do |format|
      if @post.save
        load_article_comments
        format.html { redirect_to @article, notice: "댓글이 성공적으로 작성되었습니다." }
        format.turbo_stream { render "posts/create_article_comment" }
      else
        load_article_comments
        format.html { redirect_to @article, alert: "댓글 작성에 실패했습니다." }
        format.turbo_stream { render "posts/create_article_comment", status: :unprocessable_entity }
      end
    end
  end

  def create_standalone_post
    @post = current_user.posts.build(normalized_post_params)
    @post.post_type = :short
    @post.status = :published
    @post.published_at ||= Time.current

    return create_detail_reply if params[:return_to_post].present?

    respond_to do |format|
      if @post.save
        format.turbo_stream { render Views::Posts::CreateTurboStream.new(post: @post) }
        format.html { redirect_to feed_path }
      else
        format.turbo_stream { render Views::Posts::CreateTurboStream.new(post: @post), status: :unprocessable_entity }
        format.html { redirect_to feed_path, alert: "포스트 작성에 실패했습니다." }
      end
    end
  end

  def create_detail_reply
    parent = Post.visible.find(@post.parent_id)
    root = published_thread_root(parent)
    raise ActiveRecord::RecordNotFound unless root.id.to_s == params[:return_to_post].to_s

    if save_detail_reply
      destination = root.blog? ? user_profile_blog_post_path(username: root.user.username, slug: root) : post_path(root)
      redirect_to destination, status: :see_other
    else
      render_post_show(root, reply_post: @post, status: :unprocessable_entity)
    end
  end

  def save_detail_reply
    if blank_reply_body?(@post.body)
      @post.errors.add(:body, :blank)
      return false
    end

    @post.save
  end

  def blank_reply_body?(body)
    fragment = Nokogiri::HTML5.fragment(body.to_s)
    fragment.text.tr("\u00a0", " ").blank? && fragment.at_css("img[src]").nil?
  end

  def set_article
    @article = Article.kept.find_by(slug: params[:article_id]) || Article.kept.find_by(id: params[:article_id])
    raise ActiveRecord::RecordNotFound if @article.nil?
  end

  def set_post
    @post = Post.find_by!(slug: params[:id])
  end

  def load_article_comments
    @comments = @article.posts.kept.includes(:user)
  end

  def article_comment_params
    params.expect(post: [ :body, :parent_id ])
  end

  def post_params
    params.expect(post: [ :body, :parent_id, :tag_list ])
  end

  def normalized_post_params
    attributes = post_params.to_h.symbolize_keys
    attributes[:body] = reply_body_with_mention(body: attributes[:body], parent_id: attributes[:parent_id])
    attributes
  end

  def reply_body_with_mention(body:, parent_id:)
    return body if parent_id.blank? || blank_reply_body?(body)

    parent = Post.includes(:user, :fedipub_actor).find_by(id: parent_id)
    actor = parent&.user&.fedipub_actor || parent&.fedipub_actor
    return body if actor.nil? || actor.profile_url.blank?

    return body if body.to_s.include?(actor.profile_url)

    mention_candidates = [ actor.short_at_address, actor.at_address ].compact.uniq

    mention_candidates.each do |mention_text|
      next unless body.to_s.include?(mention_text)

      return body.to_s.sub(mention_text, mention_link_for(actor, mention_text))
    end

    "#{mention_link_for(actor, default_mention_text_for(actor))} #{body}".strip
  end

  def mention_link_for(actor, text)
    helpers.link_to(text, actor.profile_url).to_s
  end

  def default_mention_text_for(actor)
    actor.local? ? actor.short_at_address : actor.at_address
  end
end
