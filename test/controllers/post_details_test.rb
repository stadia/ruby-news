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
    assert_select "#like_post_#{@blog.id} button span:not(.sr-only)", text: "1"
    assert_select "#boost_post_#{@blog.id} button span:not(.sr-only)", text: "1"
  end

  test "both reading pages provide a reply composer bound to their root" do
    sign_in @reader

    [ @blog, @short ].each do |root|
      get detail_url(root)

      assert_response :success
      assert_select "#post_form input[name='return_to_post'][value=?]", root.id.to_s
      assert_select "#post_form input[name='post[parent_id]'][value=?]", root.id.to_s
      assert_select "#post_form button[formaction=?]", new_blog_post_path, count: 0
      assert_select "#post_form lexxy-editor[attachments='false']"
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

  test "failed child reply reopens the inline composer under its parent" do
    sign_in @reader
    parent = posts(:reply_post)
    body = "<p>&nbsp;</p>"

    assert_no_difference("Post.count") { submit_reply(root: @short, parent: parent, body: body) }
    assert_response :unprocessable_entity
    assert_select "#post_#{parent.id} + #inline_reply_form"
    assert_select "#inline_reply_form [role='alert']"
    assert_select "#inline_reply_form input[name='post[parent_id]'][value=?]", parent.id.to_s
    assert_select "#inline_reply_form lexxy-editor[name='post[body]'][value=?]", body
    assert_select "#post_form [role='alert']", count: 0
    assert_select "#post_form input[name='post[parent_id]'][value=?]", @short.id.to_s
  end

  test "reading pages reply without a reply banner" do
    sign_in @reader

    [ @blog, @short ].each do |root|
      get detail_url(root)

      assert_select "[data-post-form-target='replyBanner']", count: 0
      assert_select "#post_form[data-action*='post-form:reply']", count: 0
      assert_select "template[data-thread-reply-target='template']"
    end
  end

  test "anonymous readers get an inline sign in prompt" do
    get detail_url(@short)

    assert_select "template[data-thread-reply-target='template'] #inline_reply_form a[href=?]", new_user_session_path
    assert_select "#replies_#{@short.id} #inline_reply_form", count: 0
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

  test "feed rejects markup-only replies" do
    sign_in @reader
    assert_no_difference("Post.count") do
      post posts_url, params: { post: { parent_id: @short.id, body: "<p><br></p>" } }, as: :turbo_stream
    end
    assert_response :unprocessable_entity
  end

  test "image-only detail replies require text" do
    sign_in @reader
    [ '<img src="https://example.com/image.png">', '<action-text-attachment url="https://example.com/image.png" content-type="image/png"></action-text-attachment>' ].each do |body|
      assert_no_difference("Post.count") { submit_reply(root: @short, parent: @short, body: body) }
      assert_response :unprocessable_entity
    end
  end

  test "rate limited detail reply retains body and parent" do
    sign_in @reader
    cache = ActiveSupport::Cache::MemoryStore.new
    cache.write("rate_limit:127.0.0.1:posts", 20)

    Rails.stub(:cache, cache) do
      assert_no_difference("Post.count") { submit_reply(root: @short, parent: @short, body: "보존할 댓글") }
    end
    assert_response :too_many_requests
    assert_select "#post_form [role='alert']"
    assert_select "#post_form lexxy-editor[value=?]", "보존할 댓글"
    assert_select "#post_form input[name='post[parent_id]'][value=?]", @short.id.to_s
  end

  test "rate limited child reply keeps the inline composer" do
    sign_in @reader
    parent = posts(:reply_post)
    cache = ActiveSupport::Cache::MemoryStore.new
    cache.write("rate_limit:127.0.0.1:posts", 20)

    Rails.stub(:cache, cache) do
      assert_no_difference("Post.count") { submit_reply(root: @short, parent: parent, body: "보존할 답글") }
    end
    assert_response :too_many_requests
    assert_select "#post_#{parent.id} + #inline_reply_form [role='alert']"
    assert_select "#inline_reply_form lexxy-editor[value=?]", "보존할 답글"
  end

  test "discarded child retains input on its public thread" do
    sign_in @reader
    child = posts(:reply_post)
    child.discard!
    assert_no_difference("Post.count") { submit_reply(root: @short, parent: child, body: "보존할 답글") }
    assert_response :unprocessable_entity
    assert_select "#post_form lexxy-editor[value=?]", "보존할 답글"
    assert_select "#post_form [role='alert']"
    assert_select "#post_form input[name='post[parent_id]'][value=?]", @short.id.to_s
    assert_select "#replies_#{@short.id} #inline_reply_form", count: 0
    assert_not_includes response.body, child.body
  end

  test "reply under a hidden ancestor returns input to the root composer" do
    sign_in @reader
    child = posts(:reply_post)
    grandchild = Post.create!(user: @reader, body: "<p>숨겨질 손자 답글</p>", parent: child)
    child.discard!

    assert_no_difference("Post.count") { submit_reply(root: @short, parent: grandchild, body: "보존할 답글") }
    assert_response :unprocessable_entity
    assert_select "#post_form [role='alert']", text: /#{Regexp.escape(I18n.t("posts.reply_parent_unavailable"))}/
    assert_select "#post_form lexxy-editor[value=?]", "보존할 답글"
    assert_select "#post_form input[name='post[parent_id]'][value=?]", @short.id.to_s
    assert_select "#replies_#{@short.id} #inline_reply_form", count: 0
  end

  test "published child under discarded root is unavailable" do
    sign_in @reader
    child = posts(:reply_post)
    @short.discard!
    assert_no_difference("Post.count") { submit_reply(root: @short, parent: child, body: "댓글") }
    assert_response :not_found
    get post_url(child)

    assert_response :not_found
  end

  test "draft child under published root is unavailable" do
    sign_in @reader
    child = posts(:reply_post)
    child.update!(status: :draft)
    assert_no_difference("Post.count") { submit_reply(root: @short, parent: child, body: "댓글") }
    assert_response :not_found
  end

  test "detail replies to article comments stay in article comments" do
    sign_in @reader
    root = posts(:comment_post)
    submit_reply(root: root, parent: root, body: "기사에 남긴 답글")

    assert_response :see_other
    reply = Post.order(:id).last

    assert_equal root.article_id, reply.article_id
    assert_predicate reply, :comment?
  end

  test "feed composer retains turbo and blog switching" do
    sign_in @reader
    get feed_url

    assert_response :success
    assert_select "#post_form form[data-turbo='true']"
    assert_select "#post_form input[name='return_to_post']", count: 0
    assert_select "#post_form button[formaction=?]", new_blog_post_path
  end

  test "destroyed child retains input without saving an orphan" do
    sign_in @reader
    child = Post.create!(user: @reader, body: "삭제할 답글", parent: @short)
    child.destroy!

    assert_no_difference("Post.count") { submit_reply(root: @short, parent: child, body: "보존할 답글") }
    assert_response :unprocessable_entity
    assert_select "#post_form lexxy-editor[value=?]", "보존할 답글"
    assert_select "#post_form input[name='post[parent_id]'][value=?]", @short.id.to_s
  end

  test "rate limit cannot render an unrelated thread" do
    sign_in @reader
    cache = ActiveSupport::Cache::MemoryStore.new
    cache.write("rate_limit:127.0.0.1:posts", 20)

    Rails.stub(:cache, cache) do
      assert_no_difference("Post.count") { submit_reply(root: @blog, parent: @short, body: "댓글") }
    end
    assert_response :not_found
  end

  test "rate limited feed HTML redirects with localized feedback" do
    sign_in @reader
    cache = ActiveSupport::Cache::MemoryStore.new
    cache.write("rate_limit:127.0.0.1:posts", 20)

    Rails.stub(:cache, cache) do
      assert_no_difference("Post.count") { post posts_url, params: { post: { body: "댓글" } } }
    end
    assert_redirected_to root_url
    assert_equal I18n.t("posts.rate_limit_exceeded"), flash[:alert]
  end

  test "rate limited turbo feed keeps its error response" do
    sign_in @reader
    cache = ActiveSupport::Cache::MemoryStore.new
    cache.write("rate_limit:127.0.0.1:posts", 20)

    Rails.stub(:cache, cache) do
      assert_no_difference("Post.count") do
        post posts_url, params: { post: { body: "댓글" } }, as: :turbo_stream
      end
    end
    assert_response :too_many_requests
    assert_equal "Rate limit exceeded", JSON.parse(response.body)["error"]
  end

  test "missing parent cannot turn a child into a return root" do
    sign_in @reader
    child = posts(:reply_post)

    assert_no_difference("Post.count") do
      post posts_url, params: { return_to_post: child.id, post: { parent_id: -1, body: "댓글" } }
    end
    assert_response :not_found
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
