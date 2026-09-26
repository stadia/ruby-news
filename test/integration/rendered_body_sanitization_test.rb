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

  # 서식(취소선·밑줄·색·표·코드 언어)은 렌더링 시점 정제에서도 살아남되,
  # Lexxy 팔레트가 아닌 style과 허용하지 않는 요소는 여전히 지운다.
  test "blog show keeps editor formatting while pruning unsafe styles" do
    body = %(<p><s>struck</s><u>under</u><mark style="color: var(--highlight-2);">colored</mark>) +
      %(<mark style="position: fixed; color: red">spoofed</mark></p>) +
      %(<pre data-language="ruby">puts 1</pre><table><tbody><tr><th>head</th><td>cell</td></tr></tbody></table>) + PAYLOAD
    posts(:blog_published).update_column(:body, body)

    get user_profile_blog_post_url(username: users(:john).username, slug: "lf-published-fixture")

    assert_response :success
    assert_select ".post-content s", text: "struck"
    assert_select ".post-content u", text: "under"
    assert_select ".post-content mark[style='color: var(--highlight-2);']", text: "colored"
    assert_select ".post-content mark:not([style])", text: "spoofed"
    assert_select ".post-content pre[data-language='ruby']", text: "puts 1"
    assert_select ".post-content table th", text: "head"
    assert_not_includes response.body, "position: fixed"
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
