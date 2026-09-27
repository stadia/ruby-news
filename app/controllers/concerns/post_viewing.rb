# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

# Shared "render a post thread" behavior for the two controllers that serve a
# single post's reading page: PostsController (short/comment posts at
# /posts/:slug) and BlogsController (blog posts at /@user/blog/:slug).
module PostViewing
  extend ActiveSupport::Concern

  POST_SHOW_INCLUDES = [ :user, :fedipub_actor, :article, :tags, { parent: [ :user, :fedipub_actor ] } ].freeze

  private

  # 글과 root가 모두 공개 또는 작성자 미리보기 가능한 경우에만 렌더링한다.
  # reply_post와 status로 실패한 입력과 HTTP 오류 상태를 보존한다.
  def render_post_show(post, reply_post: nil, status: :ok)
    root = post.root
    raise ActiveRecord::RecordNotFound unless viewable?(post) && viewable?(root)
    @posts = build_thread(root)
    @liked_post_ids = current_user ? Like.liked_ids_for(liker: current_user, likeable_type: "Post", likeable_ids: @posts.map(&:id)) : []
    @boosted_post_ids = current_user ? Boost.boosted_ids_for(booster: current_user, boostable_type: "Post", boostable_ids: @posts.map(&:id)) : []
    assign_blog_meta_tags(post) if post.blog?
    render Views::Posts::Show.new(posts: @posts, liked_post_ids: @liked_post_ids, boosted_post_ids: @boosted_post_ids, reply_post: reply_post), status: status
  end

  # 댓글을 받을 root가 발행되고 삭제되지 않았는지 확인한다. 스레드 일치는 호출부가 검사한다.
  def published_thread_root(post)
    root = post.root
    raise ActiveRecord::RecordNotFound unless root.kept? && root.published?

    root
  end

  # 원격 인스턴스(마스토돈 등)는 발행된 Note의 링크를 크롤링해 프리뷰 카드를
  # 만든다. 요약만 나가는 장문은 이 카드가 유일한 맥락이므로 상세 페이지에
  # article OG 태그를 채워준다.
  def assign_blog_meta_tags(post)
    @page_description = post.blog_summary
    @og_type = "article"
    @og_image = blog_og_image(post)
    @og_article = {
      published_time: post.published_at&.iso8601,
      modified_time: post.updated_at.iso8601,
      tag: post.tag_list.presence
    }.compact
  end

  # 본문 첫 이미지를 카드 썸네일로 쓰고, 없으면 레이아웃 기본 이미지로 폴백한다.
  def blog_og_image(post)
    src = Nokogiri::HTML5.fragment(post.body.to_s).at_css("img")&.[]("src")
    return nil if src.blank?

    URI.join(request.base_url, src).to_s
  rescue URI::Error
    nil
  end

  # A post is publicly viewable when visible (published & kept). The owner may
  # also preview their own draft. Discarded posts are never served here.
  def viewable?(post)
    return true if post.kept? && post.published?
    return true if post.kept? && current_user && post.user == current_user

    false
  end

  def build_thread(root)
    # 초안 자식은 작성자에게도 공개 스레드에서 노출하지 않는다.
    ids = [ root.id ] #: Array[Integer]
    queue = [ root.id ] #: Array[Integer]
    while queue.any?
      children = Post.visible.where(parent_id: queue).pluck(:id) #: Array[Integer]
      ids.concat(children)
      queue = children
    end
    Post.kept.where(id: ids).includes(POST_SHOW_INCLUDES).sort_by { |p| [ p.depth, p.created_at ] }
  end
end
