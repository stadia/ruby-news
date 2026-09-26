# frozen_string_literal: true

require "test_helper"

class BlogPostsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:john)
    @other_user = users(:jane)
    @draft = posts(:blog_draft)
    @published = posts(:blog_published)
  end

  test "requires authentication to create a draft" do
    post blog_posts_url

    assert_redirected_to new_user_session_url
  end

  test "opening the new editor does not persist a draft" do
    sign_in @user

    assert_no_difference -> { Post.blog.count } do
      get new_blog_post_url
    end

    assert_response :success
    assert_select ".post-composer-editor"
    assert_select "form[action='#{blog_posts_path}']"
  end

  test "new editor prefills body carried from the composer" do
    sign_in @user

    # The test env uses :null_store, which never retains writes. Swap in a real
    # in-memory store just for this case so the stash-then-read round-trips.
    with_memory_cache do
      assert_no_difference -> { Post.blog.count } do
        # POST keeps the body out of the URL; #new stashes it in the cache with a
        # per-request nonce so concurrent tabs don't clobber each other, then
        # redirects to the GET editor, which prefills it.
        post new_blog_post_url, params: { post: { body: "<p>이관된 본문</p>" } }

        assert_response :see_other
        follow_redirect!
      end

      assert_response :success
      assert_includes response.body, "이관된 본문"
    end
  end

  test "a stashed draft body is not readable by another user" do
    # The cache key is namespaced by current_user.id, so the nonce alone must not
    # let a different account read the body user A stashed. This is the single
    # property that distinguishes the user-scoped cache from a shared stash.
    with_memory_cache do
      sign_in @user
      post new_blog_post_url, params: { post: { body: "<p>john의 비밀 초안</p>" } }

      assert_response :see_other
      draft_key = Rack::Utils.parse_query(URI(response.location).query)["draft_key"]

      assert_predicate draft_key, :present?

      sign_out @user
      sign_in @other_user

      assert_no_difference -> { Post.blog.count } do
        get new_blog_post_url(draft_key: draft_key)
      end

      assert_response :success
      assert_not_includes response.body, "john의 비밀 초안"
    end
  end

  test "opening the editor with an unknown draft key notifies instead of silently blanking" do
    sign_in @user

    # A nonce with no matching stash (expired, consumed, or a failed write) must
    # not drop the user into a blank editor with no explanation.
    with_memory_cache do
      get new_blog_post_url(draft_key: "deadbeef")
    end

    assert_response :success
    assert_includes response.body, I18n.t("posts.blog.draft_expired")
  end

  test "a failed stash write redirects to a blank editor with an alert instead of a dead nonce" do
    sign_in @user

    # SolidCache returns false (not raise) when a write can't land; the composer
    # must not hand the editor a nonce that resolves to nothing.
    Rails.cache.stub(:write, false) do
      post new_blog_post_url, params: { post: { body: "<p>본문</p>" } }
    end

    assert_response :see_other
    assert_nil Rack::Utils.parse_query(URI(response.location).query)["draft_key"]
    assert_equal I18n.t("posts.blog.draft_stash_failed"), flash[:alert]
  end

  test "first autosave creates the draft and returns the persisted urls" do
    sign_in @user

    assert_difference -> { Post.blog.draft.count }, 1 do
      post blog_posts_url, params: { post: { title: "초안", body: "<p>본문</p>" } }, as: :json
    end

    assert_response :success
    draft = Post.blog.draft.order(:id).last

    assert_equal @user, draft.user
    body = response.parsed_body

    assert_equal blog_post_path(draft, format: :json), body["save_url"]
    assert_equal publish_blog_post_path(draft), body["publish_url"]
  end

  test "publishing a new draft creates and publishes in one request" do
    sign_in @user

    assert_difference -> { Post.blog.published.count }, 1 do
      post blog_posts_url, params: { post: { title: "제목", body: "<p>본문</p>" }, publish: "1" }
    end

    published = Post.blog.published.order(:id).last

    assert_equal "제목", published.slug
    assert_redirected_to "http://example.com/@#{published.user.username}/blog/#{ERB::Util.url_encode("제목")}"
    follow_redirect!

    assert_response :success
  end

  test "publishing a new draft without a title re-renders the editor" do
    sign_in @user

    assert_no_difference -> { Post.blog.count } do
      post blog_posts_url, params: { post: { title: "", body: "<p>본문</p>" }, publish: "1" }
    end

    assert_response :unprocessable_entity
  end

  test "renders edit page for owner draft" do
    sign_in @user
    get edit_blog_post_url(@draft)

    assert_response :success
    assert_select "h1", "블로그 쓰기"
  end

  test "edit page renders blog editor form" do
    sign_in @user

    get edit_blog_post_url(@draft)

    assert_response :success
    assert_select "form[action='#{blog_post_path(@draft)}']"
    assert_select "input[name='post[title]']"
    assert_select "[data-controller~='blog-autosave']"
    assert_select ".post-composer-editor"
    assert_select "button", "발행"
  end

  test "edit page hands saved image figures to the editor as captioned attachments" do
    @draft.update!(body: %(<figure><img src="/a.png" alt="대체 텍스트"><figcaption>사진 설명</figcaption></figure>))
    sign_in @user

    get edit_blog_post_url(@draft)

    assert_response :success
    value = Nokogiri::HTML5.fragment(css_select("lexxy-editor").first["value"])

    assert_equal "사진 설명", value.at_css("action-text-attachment")&.[]("caption"), value.to_html
    assert_nil value.at_css("figcaption"), value.to_html
  end

  test "does not allow editing another user's draft" do
    @draft.update!(user: @other_user)
    sign_in @user
    get edit_blog_post_url(@draft)

    assert_redirected_to feed_url
  end

  test "autosaves draft fields" do
    sign_in @user
    patch blog_post_url(@draft), params: {
      post: { title: "자동 저장 제목", body: "<p>자동 저장 본문</p>", tag_list: "ruby, rails" }
    }, as: :json

    assert_response :success
    assert_equal "자동 저장 제목", @draft.reload.title
    assert_equal [ "rails", "ruby" ], @draft.tag_list.sort
  end

  test "publishes a complete draft" do
    sign_in @user
    @draft.update!(title: "발행 제목", body: "<p>발행 본문</p>")
    patch publish_blog_post_url(@draft)

    assert_predicate @draft.reload, :published?
    assert_equal "발행-제목", @draft.slug
    assert_redirected_to user_profile_blog_post_url(username: @draft.user.username, slug: @draft)
    assert_not_nil @draft.published_at
  end

  test "autosaved draft publishes under a slug from the title at publish time" do
    sign_in @user
    post blog_posts_url, params: { post: { title: "처음 제목", body: "<p>본문</p>" } }, as: :json
    draft = Post.blog.draft.order(:id).last
    patch blog_post_url(draft, format: :json), params: { post: { title: "바뀐 제목 & 발행" } }, as: :json

    patch publish_blog_post_url(draft)

    assert_equal "바뀐-제목-발행", draft.reload.slug
    assert_redirected_to user_profile_blog_post_url(username: @user.username, slug: "바뀐-제목-발행")
    follow_redirect!

    assert_response :success
  end

  test "failed publish keeps the editor pointed at the saved draft slug" do
    sign_in @user
    @draft.update!(title: "", body: "<p>본문</p>")

    patch publish_blog_post_url(@draft), params: { post: { title: "" } }

    assert_response :unprocessable_entity
    assert_select "form[action='#{blog_post_path(@draft)}']"
    assert_equal "lf-draft-fixture", @draft.reload.slug
  end

  test "does not publish incomplete draft" do
    sign_in @user
    @draft.update!(title: "", body: "<p>본문</p>")
    patch publish_blog_post_url(@draft)

    assert_response :unprocessable_entity
    assert_predicate @draft.reload, :draft?
  end

  test "updates a published blog post" do
    sign_in @user
    patch blog_post_url(@published), params: {
      post: { title: "수정된 제목", body: "<p>수정된 본문</p>" }
    }

    assert_redirected_to user_profile_blog_post_url(username: @published.user.username, slug: "lf-published-fixture")
    assert_equal "수정된 제목", @published.reload.title
    assert_equal "lf-published-fixture", @published.slug
  end

  test "requires authentication to delete" do
    delete blog_post_url(@draft)

    assert_redirected_to new_user_session_url
  end

  test "soft-discards a draft and redirects" do
    sign_in @user

    delete blog_post_url(@draft)

    assert_redirected_to feed_url
    assert_predicate @draft.reload, :discarded?
    assert_predicate Post.where(id: @draft.id), :exists?
  end

  test "deleting a draft does not create a Delete activity" do
    sign_in @user

    assert_no_difference -> { Fedipub::Activity.where(action: "Delete").count } do
      delete blog_post_url(@draft)
    end
  end

  test "soft-discards a published blog post" do
    sign_in @user

    delete blog_post_url(@published)

    assert_predicate @published.reload, :discarded?
  end

  test "deleting a published blog federates a Delete activity" do
    sign_in @user

    assert_difference -> { Fedipub::Activity.where(action: "Delete", entity: @published).count }, 1 do
      delete blog_post_url(@published)
    end
  end

  test "does not allow deleting another user's post" do
    @draft.update!(user: @other_user)
    sign_in @user

    delete blog_post_url(@draft)

    assert_not_predicate @draft.reload, :discarded?
  end

  test "discarded blog is excluded from owner profile list" do
    sign_in @user
    @published.discard!

    get user_profile_posts_url(username: @user.username)

    assert_response :success
    assert_not_includes response.body, @published.title
  end

  test "undiscard requires authentication" do
    @published.discard!

    patch undiscard_blog_post_url(@published)

    assert_redirected_to new_user_session_url
    assert_predicate @published.reload, :discarded?
  end

  test "undiscard restores a discarded post for the owner" do
    sign_in @user
    @published.discard!

    patch undiscard_blog_post_url(@published)

    assert_redirected_to account_blog_url
    assert_not_predicate @published.reload, :discarded?
    assert_nil @published.deleted_at
  end

  test "undiscarding a published post federates an Undo activity" do
    sign_in @user
    @published.discard!

    assert_difference -> { Fedipub::Activity.where(action: "Undo", entity: @published).count }, 1 do
      patch undiscard_blog_post_url(@published)
    end
  end

  test "non-owner cannot undiscard a post" do
    @published.update!(user: @other_user)
    @published.discard!
    sign_in @user

    patch undiscard_blog_post_url(@published)

    assert_predicate @published.reload, :discarded?
  end

  test "destroy_permanently requires authentication" do
    @published.discard!

    delete destroy_permanently_blog_post_url(@published)

    assert_redirected_to new_user_session_url
    assert_predicate Post.where(id: @published.id), :exists?
  end

  test "destroy_permanently removes the row for the owner" do
    sign_in @user
    @draft.discard!

    delete destroy_permanently_blog_post_url(@draft)

    assert_redirected_to account_blog_url
    assert_not Post.where(id: @draft.id).exists?
  end

  test "destroy_permanently on a published post federates a Delete activity" do
    sign_in @user
    @published.discard!

    assert_difference -> { Fedipub::Activity.where(action: "Delete", entity: @published).count }, 1 do
      delete destroy_permanently_blog_post_url(@published)
    end
  end

  test "non-owner cannot permanently destroy a post" do
    @published.update!(user: @other_user)
    @published.discard!
    sign_in @user

    delete destroy_permanently_blog_post_url(@published)

    assert_predicate Post.where(id: @published.id), :exists?
  end

  test "index requires authentication" do
    get account_blog_url

    assert_redirected_to new_user_session_url
  end

  test "index shows the owner's drafts with edit and delete controls" do
    sign_in @user

    get account_blog_url

    assert_response :success
    assert_includes response.body, I18n.t("profiles.blog_list.drafts_heading")
    assert_includes response.body, @draft.title
    assert_select "a[href=?]", edit_blog_post_path(@draft)
    assert_select "form[action=?]", blog_post_path(@draft)
  end

  test "index lists published posts linking to the public permalink" do
    sign_in @user

    get account_blog_url

    assert_response :success
    assert_includes response.body, @published.title
    assert_select "a[href=?]", user_profile_blog_post_path(username: @user.username, slug: @published)
  end

  test "index drafts exclude trashed drafts and offer restore" do
    sign_in @user
    @draft.discard!

    get account_blog_url

    assert_response :success
    assert_select "form[action=?]", undiscard_blog_post_path(@draft)
    assert_select "a[href=?]", edit_blog_post_path(@draft), count: 0
  end

  test "index trash section lists discarded published posts with restore and destroy" do
    sign_in @user
    @published.discard!

    get account_blog_url

    assert_response :success
    assert_select "form[action=?]", undiscard_blog_post_path(@published)
    assert_select "form[action=?]", destroy_permanently_blog_post_path(@published)
  end

  test "index trash section shows empty state when nothing discarded" do
    sign_in @user

    get account_blog_url

    assert_response :success
    assert_includes response.body, I18n.t("profiles.blog_list.trash_empty")
  end

  test "한글 slug로 발행한 글의 관리 경로에서 편집 수정 삭제할 수 있다" do
    sign_in @user
    @draft.update!(title: "한글 관리", body: "<p>본문</p>")
    @draft.publish!
    path = "/blog_posts/#{ERB::Util.url_encode("한글-관리")}"

    get "#{path}/edit"

    assert_response :success
    patch path, params: { post: { title: "수정 제목" } }

    assert_response :redirect
    assert_equal "한글-관리", @draft.reload.slug
    delete path

    assert_response :redirect
    assert_predicate @draft.reload, :discarded?
  end

  test "관리 경로도 대소문자·NFD가 다른 slug로 글을 찾는다" do
    sign_in @user
    @draft.update!(title: "Ruby 관리", body: "<p>본문</p>")
    @draft.publish!

    get "/blog_posts/#{ERB::Util.url_encode("RUBY-관리".unicode_normalize(:nfd))}/edit"

    assert_response :success
  end

  private

  # test.rb pins the cache to :null_store, so any code under test that relies on
  # Rails.cache round-tripping needs a real store for the duration of the block.
  # Rails.stub restores the original store on block exit and avoids the global
  # reassignment footgun if the suite ever moves to thread-based parallelism.
  def with_memory_cache(&)
    Rails.stub(:cache, ActiveSupport::Cache::MemoryStore.new, &)
  end
end
