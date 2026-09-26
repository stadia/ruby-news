# frozen_string_literal: true

require "test_helper"

class PostDetailsTest < ActionDispatch::IntegrationTest
  setup do
    @reader = users(:jane)
    @blog = posts(:blog_published)
    @short = posts(:root_post)
    @short.update!(slug: "detail-short")
  end

  test "published blog shows reaction buttons and anonymous reply login" do
    get blog_url(@blog)

    assert_response :success
    assert_select "form[action=?]", post_like_path(@blog)
    assert_select "form[action=?]", post_boost_path(@blog)
    assert_select "a[href=?]", new_user_session_path, text: I18n.t("posts.show.sign_in_to_reply")
    assert_select "#post_form", count: 0
  end

  test "blog reflects reaction counts and undo states" do
    sign_in @reader
    @reader.like!(@blog)
    @reader.boost!(@blog)

    get blog_url(@blog)

    assert_select "#like_post_#{@blog.id} input[name='_method'][value='delete']"
    assert_select "#boost_post_#{@blog.id} input[name='_method'][value='delete']"
    assert_select "#like_post_#{@blog.id} button", text: /1/
    assert_select "#boost_post_#{@blog.id} button", text: /1/
  end

  test "both reading pages provide a reply composer bound to their root" do
    sign_in @reader

    [ @blog, @short ].each do |root|
      get detail_url(root)

      assert_response :success
      assert_select "#post_form input[name='return_to_post'][value=?]", root.id.to_s
      assert_select "#post_form input[name='post[parent_id]'][value=?]", root.id.to_s
      assert_select "#post_form button[formaction=?]", new_blog_post_path, count: 0
    end
  end

  test "short post provides anonymous reply login" do
    get post_url(@short)

    assert_response :success
    assert_select "a[href=?]", new_user_session_path, text: I18n.t("posts.show.sign_in_to_reply")
    assert_select "#post_form", count: 0
  end

  test "draft preview keeps owner controls without interaction controls" do
    draft = posts(:blog_draft)
    sign_in draft.user

    get blog_url(draft)

    assert_response :success
    assert_select "a[href=?]", edit_blog_post_path(draft)
    assert_select "form[action=?]", post_like_path(draft), count: 0
    assert_select "form[action=?]", post_boost_path(draft), count: 0
    assert_select "#post_form", count: 0
  end

  test "detail replies return to each original reading page with the new reply" do
    sign_in @reader

    [ @blog, @short ].each do |root|
      assert_difference("Post.count") do
        submit_reply(root: root, parent: root, body: "상세 화면에서 작성한 댓글")
      end
      assert_response :see_other
      assert_redirected_to detail_url(root)
      follow_redirect!

      assert_includes response.body, "상세 화면에서 작성한 댓글"
      assert_select "#post_form input[name='post[parent_id]'][value=?]", root.id.to_s
      assert_select "h1", text: @blog.title if root.blog?
    end
  end

  test "detail can reply to a child while returning to the root thread" do
    sign_in @reader
    parent = posts(:reply_post)

    submit_reply(root: @short, parent: parent, body: "댓글에 대한 답글")

    assert_redirected_to post_url(@short)
    reply = Post.order(:id).last

    assert_equal parent.id, reply.parent_id
    assert_equal 2, reply.depth
  end

  test "blank detail reply is not turned into a mention-only reply" do
    sign_in @reader

    [ @blog, @short ].each do |root|
      [ "   ", "<p><br></p>" ].each do |body|
        assert_no_difference("Post.count") { submit_reply(root: root, parent: root, body: body) }
        assert_response :unprocessable_entity
      end
      assert_response :unprocessable_entity
      assert_select "#post_form [role='alert']"
      assert_select "#post_form input[name='post[parent_id]'][value=?]", root.id.to_s
      assert_select "h1", text: @blog.title if root.blog?
    end
  end

  test "detail replies require authentication" do
    assert_no_difference("Post.count") { submit_reply(root: @blog, parent: @blog, body: "未認証") }
    assert_redirected_to new_user_session_url
  end

  test "detail replies reject draft parents" do
    sign_in @reader
    draft = posts(:blog_draft)

    assert_no_difference("Post.count") { submit_reply(root: draft, parent: draft, body: "댓글") }
    assert_response :not_found
  end

  test "detail replies reject discarded parents" do
    sign_in @reader
    deleted = Post.create!(user: @reader, body: "삭제된 부모")
    deleted.discard!

    assert_no_difference("Post.count") { submit_reply(root: deleted, parent: deleted, body: "댓글") }
    assert_response :not_found
  end

  test "failed child reply retains input and selected parent" do
    sign_in @reader
    parent = posts(:reply_post)
    body = "<p>&nbsp;</p>"

    assert_no_difference("Post.count") { submit_reply(root: @short, parent: parent, body: body) }
    assert_response :unprocessable_entity
    assert_select "#post_form [role='alert']"
    assert_select "#post_form input[name='post[parent_id]'][value=?]", parent.id.to_s
    assert_select "#post_form lexxy-editor[name='post[body]'][value=?]", body
  end

  test "detail replies reject a child under an unpublished root" do
    sign_in @reader
    draft = posts(:blog_draft)
    child = Post.create!(user: @reader, body: "초안의 자식", parent: draft)

    assert_no_difference("Post.count") { submit_reply(root: draft, parent: child, body: "댓글") }
    assert_response :not_found
  end

  test "detail replies reject parents outside the requested thread" do
    sign_in @reader

    assert_no_difference("Post.count") { submit_reply(root: @blog, parent: @short, body: "다른 스레드") }
    assert_response :not_found
  end

  test "public child URL cannot expose a draft root" do
    draft = posts(:blog_draft)
    child = Post.create!(user: @reader, body: "발행된 답글", parent: draft)

    get post_url(child)

    assert_response :not_found
    assert_not_includes response.body, draft.body
  end

  test "public reading pages do not expose unpublished descendants" do
    draft = Post.create!(user: @reader, body: "비공개 답글", status: :draft, parent: @short)

    get post_url(@short)

    assert_response :success
    assert_not_includes response.body, draft.body
  end

  private

  def blog_url(blog)
    user_profile_blog_post_url(username: blog.user.username, slug: blog)
  end

  def detail_url(root)
    root.blog? ? blog_url(root) : post_url(root)
  end

  def submit_reply(root:, parent:, body:)
    post posts_url, params: { return_to_post: root.id, post: { parent_id: parent.id, body: body } }
  end
end
