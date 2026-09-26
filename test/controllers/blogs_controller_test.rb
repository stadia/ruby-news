# frozen_string_literal: true

require "test_helper"

class BlogsControllerTest < ActionDispatch::IntegrationTest
  test "shows a published blog post with the reading layout to anyone" do
    post = posts(:blog_published)

    get user_profile_blog_post_url(username: post.user.username, slug: post)

    assert_response :success
    assert_includes response.body, post.title
  end

  # 마스토돈 등 원격 클라이언트가 링크 프리뷰 카드를 만들 수 있도록,
  # 장문 상세는 요약을 og:description으로 노출한다.
  test "published blog post exposes article open graph tags" do
    post = posts(:blog_published)

    get user_profile_blog_post_url(username: post.user.username, slug: post)

    assert_includes response.body, %(<meta property="og:type" content="article">)
    assert_includes response.body, %(<meta property="og:description" content="#{post.blog_summary}">)
    assert_includes response.body, %(<meta property="og:title" content="#{post.title}">)
  end

  test "blog post with a body image uses it as the preview card image" do
    post = posts(:blog_published)
    post.update!(body: %(<p>본문</p><img src="/uploads/cover.png">))

    get user_profile_blog_post_url(username: post.user.username, slug: post)

    assert_includes response.body, %(<meta property="og:image" content="http://example.com/uploads/cover.png">)
  end

  test "draft blog post is not served to anonymous visitors" do
    draft = posts(:blog_draft)

    get user_profile_blog_post_url(username: draft.user.username, slug: draft)

    assert_response :not_found
  end

  test "draft blog post is not served to a non-owner" do
    draft = posts(:blog_draft)
    sign_in users(:jane)

    get user_profile_blog_post_url(username: draft.user.username, slug: draft)

    assert_response :not_found
  end

  test "owner can preview their own draft blog post" do
    draft = posts(:blog_draft)
    sign_in draft.user

    get user_profile_blog_post_url(username: draft.user.username, slug: draft)

    assert_response :success
  end

  test "discarded blog post is not served publicly" do
    post = posts(:blog_published)
    post.discard!

    get user_profile_blog_post_url(username: post.user.username, slug: post)

    assert_response :not_found
  end

  test "correct slug under the wrong username is not found" do
    post = posts(:blog_published)

    get user_profile_blog_post_url(username: users(:jane).username, slug: post)

    assert_response :not_found
  end

  test "serves a newly published post under its percent-encoded Korean title slug" do
    post = users(:john).posts.new(post_type: :blog, title: "한글 제목, 그리고 Rails!", body: "<p>본문</p>")
    post.publish!

    get "/@#{post.user.username}/blog/#{ERB::Util.url_encode('한글-제목-그리고-rails')}"

    assert_response :success
    assert_includes response.body, "한글 제목, 그리고 Rails!"
  end

  test "keeps serving a post at its original slug after the title changes" do
    post = users(:john).posts.new(post_type: :blog, title: "원래 제목", body: "<p>본문</p>")
    post.publish!
    post.update!(title: "수정한 제목")

    get user_profile_blog_post_url(username: post.user.username, slug: "원래-제목")

    assert_response :success
  end

  test "redirects a differently cased slug to the canonical URL" do
    post = users(:john).posts.new(post_type: :blog, title: "Ruby 소식", body: "<p>본문</p>")
    post.publish!

    get "/@#{post.user.username}/blog/#{ERB::Util.url_encode('RUBY-소식')}"

    assert_response :moved_permanently
    assert_redirected_to "http://www.example.com/@#{post.user.username}/blog/#{ERB::Util.url_encode('ruby-소식')}"
  end

  test "redirects an NFD-encoded Korean slug to the canonical NFC URL" do
    post = users(:john).posts.new(post_type: :blog, title: "한글 소식", body: "<p>본문</p>")
    post.publish!

    get "/@#{post.user.username}/blog/#{ERB::Util.url_encode('한글-소식'.unicode_normalize(:nfd))}"

    assert_response :moved_permanently
    assert_redirected_to "http://www.example.com/@#{post.user.username}/blog/#{ERB::Util.url_encode('한글-소식')}"
  end
end
