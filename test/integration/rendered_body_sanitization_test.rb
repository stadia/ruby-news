# frozen_string_literal: true

require "test_helper"

# SEC-02 defense-in-depth: every UGC body render site sanitizes at render time
# with HtmlSanitizable::ALLOWED_TAGS, independent of the save-time sanitize.
#
# Bodies are written with update_column so they bypass the before_save
# sanitize_body callback — this simulates a row that reached the DB with unsafe
# markup (pre-existing data, a future write path, or the save-time guard being
# weakened). If a render site drops its sanitize call or widens the allowlist,
# the disallowed tag survives and these tests fail.
class RenderedBodySanitizationTest < ActionDispatch::IntegrationTest
  # <p> is allowed and must survive; <iframe> is disallowed, so the whole tag —
  # including its src marker — must be pruned. (An iframe is used rather than a
  # script tag because the sanitizer strips the tag but keeps a script tag's text
  # content, whereas an iframe's src lives in an attribute that vanishes with it.)
  PAYLOAD = %(<p>safe body</p><iframe src="//evil.test/c2-xss"></iframe>)
  DISALLOWED_MARKER = "evil.test"

  test "blog show (Views::Posts::Show) sanitizes the root body at render time" do
    posts(:blog_published).update_column(:body, PAYLOAD)

    get user_profile_blog_post_url(username: users(:john).username, slug: "lf-published-fixture")

    assert_response :success
    assert_includes response.body, "safe body"
    assert_not_includes response.body, DISALLOWED_MARKER
  end

  # The blog allowlist is wider than the short-post one (section headings and
  # image figures from the editor), but it must still prune disallowed markup.
  test "blog show keeps blog-only tags while still pruning disallowed markup" do
    body = %(<h2>section heading</h2><figure><img src="https://cdn.example/a.webp" alt="alt text">) +
      %(<figcaption>figure caption</figcaption></figure>) + PAYLOAD
    posts(:blog_published).update_column(:body, body)

    get user_profile_blog_post_url(username: users(:john).username, slug: "lf-published-fixture")

    assert_response :success
    assert_select ".post-content h2", text: "section heading"
    assert_select ".post-content figure img[src='https://cdn.example/a.webp'][alt='alt text']"
    assert_select ".post-content figure figcaption", text: "figure caption"
    assert_not_includes response.body, DISALLOWED_MARKER
  end

  test "post show (Components::Posts::PostCard) sanitizes the body at render time" do
    posts(:short_with_article).update_column(:body, PAYLOAD)

    get post_url("lf-short-fixture")

    assert_response :success
    assert_includes response.body, "safe body"
    assert_not_includes response.body, DISALLOWED_MARKER
  end

  test "article comments (Components::Comments::Comment) sanitize the body at render time" do
    posts(:comment_post).update_column(:body, PAYLOAD)

    get article_url("ruby-3-4-features")

    assert_response :success
    assert_includes response.body, "safe body"
    assert_not_includes response.body, DISALLOWED_MARKER
  end
end
