# frozen_string_literal: true

require "test_helper"

# Direct coverage for the extracted Posts::FederationIngest concern (inbound
# ActivityPub parsing). Reply-target resolution is also exercised in
# post_test.rb; these tests pin the currently-undocumented edge cases:
# article_id value-type inconsistency, discarded-parent resolution, hashtag
# prefix handling, and the missing-id path.
class Posts::FederationIngestTest < ActiveSupport::TestCase
  def setup
    @article = articles(:ruby_article)
    @root_post = posts(:root_post)
    @comment_post = posts(:comment_post) # post_type :comment, belongs to ruby_article
    @local_host = Rails.application.routes.default_url_options[:host] || "www.example.com"
  end

  # ── article_id / parent_id value type ───────────────────────────────
  #
  # Every branch normalizes the id to Integer, so the regex-capture branches
  # agree with the DB-column branches (issue #871, item 1).

  test "article_id from a local /articles/ URL is an Integer" do
    hash = { "id" => "https://remote.example.com/notes/a", "content" => "댓글",
             "inReplyTo" => "https://#{@local_host}/articles/#{@article.id}" }
    result = Post.from_activitypub_object(hash)

    assert_equal @article.id, result[:article_id]
    assert_kind_of Integer, result[:article_id]
    assert_equal :comment, result[:post_type]
  end

  test "article_id from a federated parent is an Integer" do
    parent = Post.create!(body: "미러링된 리모트 기사", fedipub_actor: fedipub_actors(:john_actor),
                          federated_url: "https://hackers.pub/ap/notes/parent-1", article: @article)
    hash = { "id" => "https://hackers.pub/ap/notes/child-1", "content" => "답글",
             "inReplyTo" => "https://hackers.pub/ap/notes/parent-1" }
    result = Post.from_activitypub_object(hash)

    assert_equal parent.id, result[:parent_id]
    assert_equal @article.id, result[:article_id]
    assert_kind_of Integer, result[:article_id]
  end

  # ── discarded parent (verified actual behavior) ─────────────────────
  #
  # Post has no `kept` default_scope, so Post.find_by / Post.exists? DO see
  # soft-deleted rows. A reply to a discarded parent therefore resolves
  # normally rather than being orphaned. Pinned to lock in the real behavior.

  test "reply to a discarded federated parent still resolves parent_id and article_id" do
    parent = Post.create!(body: "삭제된 원격 부모", fedipub_actor: fedipub_actors(:john_actor),
                          federated_url: "https://remote.example.com/notes/discarded", article: @article)
    parent.discard!

    hash = { "id" => "https://remote.example.com/notes/reply-to-discarded", "content" => "답글",
             "inReplyTo" => "https://remote.example.com/notes/discarded" }
    result = Post.from_activitypub_object(hash)

    assert_equal parent.id, result[:parent_id]
    assert_equal @article.id, result[:article_id]
  end

  test "handle_federated_object? accepts a reply to a discarded parent's federated_url" do
    parent = Post.create!(body: "삭제된 원격 부모", fedipub_actor: fedipub_actors(:john_actor),
                          federated_url: "https://remote.example.com/notes/discarded-2")
    parent.discard!

    hash = { "id" => "https://remote.example.com/notes/reply-to-discarded",
             "type" => "Note", "inReplyTo" => "https://remote.example.com/notes/discarded-2" }

    assert Post.send(:handle_federated_object?, hash)
  end

  # ── id-less objects ─────────────────────────────────────────────────
  #
  # An object without "id" must be rejected at the inbox filter, not merely
  # logged. fedipub looks the entity up with
  # `find_by federated_url: hash['id']` (utils/object.rb), and every *local*
  # post has federated_url NULL (the gem's own `local_fedipub_entities`
  # scope is `where federated_url: nil`). So a nil id matches an arbitrary
  # local post, and an Update activity then overwrites it via
  # `assign_attributes` + `save!` (data_entity.rb).

  test "handle_federated_object? rejects an object with no id" do
    hash = { "type" => "Note", "content" => "id 없는 객체" }

    assert_not Post.send(:handle_federated_object?, hash)
  end

  test "handle_federated_object? rejects an id-less object even when it replies to a local post" do
    hash = { "type" => "Note", "content" => "id 없는 답글",
             "inReplyTo" => "https://#{@local_host}/posts/#{@root_post.id}" }

    assert_not Post.send(:handle_federated_object?, hash)
  end

  # ── local host matching is case-insensitive ─────────────────────────
  #
  # Host names are case-insensitive per DNS, and URI.parse preserves the case
  # it was given. A reply to https://RUBY-NEWS.DEV/posts/1 must resolve the
  # same as the lowercase form; otherwise it is classified remote, rejected by
  # handle_federated_object?, and the reply is silently lost.

  test "local host matching ignores case" do
    upcased = @local_host.upcase
    hash = { "id" => "https://remote.example.com/notes/upcased", "content" => "답글",
             "inReplyTo" => "https://#{upcased}/posts/#{@root_post.id}" }

    assert Post.send(:handle_federated_object?, hash)
    assert_equal @root_post.id, Post.from_activitypub_object(hash)[:parent_id]
  end

  # ── local /posts/ branch ────────────────────────────────────────────

  test "local /posts/ URL pointing at a comment fills both parent_id and article_id" do
    hash = { "id" => "https://remote.example.com/notes/b", "content" => "답글",
             "inReplyTo" => "https://#{@local_host}/posts/#{@comment_post.id}" }
    result = Post.from_activitypub_object(hash)

    assert_equal @comment_post.id, result[:parent_id]
    assert_kind_of Integer, result[:parent_id]
    assert_equal @comment_post.article_id, result[:article_id]
  end

  test "a missing local post is rejected instead of becoming a standalone post" do
    missing_id = Post.maximum(:id).to_i + 1_000
    hash = { "id" => "https://remote.example.com/notes/gone", "content" => "답글",
             "inReplyTo" => "https://#{@local_host}/posts/#{missing_id}" }

    assert_not Post.send(:handle_federated_object?, hash)
    assert_raises(ActiveRecord::RecordNotFound) { Post.from_activitypub_object(hash) }
  end

  test "a local post public slug URL resolves to its parent" do
    @root_post.update_columns(slug: "root-slug-for-reply")
    hash = { "id" => "https://remote.example.com/notes/slug-reply", "content" => "답글",
             "inReplyTo" => @root_post.public_url }

    assert_match %r{/posts/root-slug-for-reply\z}, hash["inReplyTo"]
    assert Post.send(:handle_federated_object?, hash)
    assert_equal @root_post.id, Post.from_activitypub_object(hash)[:parent_id]
  end

  test "a missing local post slug is rejected" do
    hash = { "id" => "https://remote.example.com/notes/missing-slug", "content" => "답글",
             "inReplyTo" => "https://#{@local_host}/posts/no-such-post" }

    assert_not Post.send(:handle_federated_object?, hash)
    assert_raises(ActiveRecord::RecordNotFound) { Post.from_activitypub_object(hash) }
  end

  test "a local published post URL resolves to its parent" do
    hash = { "id" => "https://remote.example.com/notes/published-reply", "content" => "답글",
             "inReplyTo" => published_url("posts", @root_post.id) }

    assert Post.send(:handle_federated_object?, hash)
    assert_equal @root_post.id, Post.from_activitypub_object(hash)[:parent_id]
  end

  test "a local published article URL resolves to a comment" do
    hash = { "id" => "https://remote.example.com/notes/published-article-reply", "content" => "답글",
             "inReplyTo" => published_url("articles", @article.id) }

    assert Post.send(:handle_federated_object?, hash)
    result = Post.from_activitypub_object(hash)

    assert_equal @article.id, result[:article_id]
    assert_nil result[:parent_id]
    assert_equal :comment, result[:post_type]
  end

  test "a missing local published article is rejected" do
    hash = { "id" => "https://remote.example.com/notes/missing-published-article", "content" => "답글",
             "inReplyTo" => published_url("articles", Article.maximum(:id).to_i + 1_000) }

    assert_not Post.send(:handle_federated_object?, hash)
    assert_raises(ActiveRecord::RecordNotFound) { Post.from_activitypub_object(hash) }
  end

  # 예전에 발행된 /posts/N 주소는 slug가 생긴 뒤에도 풀려야 한다.
  test "a numeric local post URL resolves a post that has a slug" do
    @root_post.update_columns(slug: "root-numeric-reply")
    hash = { "id" => "https://remote.example.com/notes/numeric-reply", "content" => "답글",
             "inReplyTo" => "https://#{@local_host}/posts/#{@root_post.id}" }

    assert Post.send(:handle_federated_object?, hash)
    assert_equal @root_post.id, Post.from_activitypub_object(hash)[:parent_id]
  end

  # ArticlesController와 같은 순서(slug → id)로 찾아야 댓글이 다른 기사에 붙지 않는다.
  test "a slug that looks like another article's id wins over the id" do
    other = articles(:korean_content_article)
    other.update_columns(slug: @article.id.to_s)
    hash = { "id" => "https://remote.example.com/notes/slug-vs-id", "content" => "답글",
             "inReplyTo" => "https://#{@local_host}/articles/#{@article.id}" }

    assert_equal other.id, Post.from_activitypub_object(hash)[:article_id]
  end

  # 디코딩 결과가 DB에 넘길 수 없는 문자열이면 PG 오류(500)가 아니라 대상 없음(404)으로 처리한다.
  [ "/posts/%FF", "/posts/%00", "/articles/%C3%28", "/articles/%00" ].each do |path|
    test "an undecodable local slug #{path} is rejected as a missing target" do
      hash = { "id" => "https://remote.example.com/notes/undecodable", "content" => "답글",
               "inReplyTo" => "https://#{@local_host}#{path}" }

      assert_not Post.send(:handle_federated_object?, hash)
      assert_raises(ActiveRecord::RecordNotFound) { Post.from_activitypub_object(hash) }
    end
  end

  test "a local post URL with a trailing slash resolves to its parent" do
    @root_post.update_columns(slug: "root-slash-reply")
    hash = { "id" => "https://remote.example.com/notes/slash-reply", "content" => "답글",
             "inReplyTo" => "https://#{@local_host}/posts/#{@root_post.slug}/" }

    assert Post.send(:handle_federated_object?, hash)
    assert_equal @root_post.id, Post.from_activitypub_object(hash)[:parent_id]
  end

  test "a local post HTML URL resolves to its parent" do
    @root_post.update_columns(slug: "root-html-reply")
    hash = { "id" => "https://remote.example.com/notes/html-reply", "content" => "답글",
             "inReplyTo" => "https://#{@local_host}/posts/#{@root_post.slug}.html" }

    assert Post.send(:handle_federated_object?, hash)
    assert_equal @root_post.id, Post.from_activitypub_object(hash)[:parent_id]
  end

  test "a missing local article is rejected instead of becoming a comment" do
    missing_id = Article.maximum(:id).to_i + 1_000
    hash = { "id" => "https://remote.example.com/notes/missing-article", "content" => "답글",
             "inReplyTo" => "https://#{@local_host}/articles/#{missing_id}" }

    assert_not Post.send(:handle_federated_object?, hash)
    assert_raises(ActiveRecord::RecordNotFound) { Post.from_activitypub_object(hash) }
  end

  test "a local article public slug URL resolves to a comment" do
    hash = { "id" => "https://remote.example.com/notes/article-slug-reply", "content" => "답글",
             "inReplyTo" => Rails.application.routes.url_helpers.article_url(@article) }

    assert Post.send(:handle_federated_object?, hash)
    result = Post.from_activitypub_object(hash)

    assert_equal @article.id, result[:article_id]
    assert_equal :comment, result[:post_type]
  end

  test "a local article Markdown URL resolves to a comment" do
    hash = { "id" => "https://remote.example.com/notes/article-markdown-reply", "content" => "답글",
             "inReplyTo" => Rails.application.routes.url_helpers.article_url(@article, format: :md) }

    assert Post.send(:handle_federated_object?, hash)
    result = Post.from_activitypub_object(hash)

    assert_equal @article.id, result[:article_id]
    assert_equal :comment, result[:post_type]
  end

  test "a local URL with a post path only in its query is rejected" do
    hash = { "id" => "https://remote.example.com/notes/query-target", "content" => "답글",
             "inReplyTo" => "https://#{@local_host}/unrelated?next=/posts/#{@root_post.id}" }

    assert_not Post.send(:handle_federated_object?, hash)
    assert_raises(ActiveRecord::RecordNotFound) { Post.from_activitypub_object(hash) }
  end

  # ── hashtag parsing ─────────────────────────────────────────────────

  test "hashtags are stripped of leading # deduplicated and comma-joined" do
    hash = { "id" => "https://remote.example.com/notes/tags", "content" => "본문",
             "tag" => [
               { "type" => "Hashtag", "name" => "#ruby" },
               { "type" => "Hashtag", "name" => "rails" },
               { "type" => "Hashtag", "name" => "#ruby" },
               { "type" => "Mention", "name" => "@someone" }
             ] }
    result = Post.from_activitypub_object(hash)

    assert_equal "ruby, rails", result[:tag_list]
  end

  test "tag_list is absent when there are no hashtags" do
    hash = { "id" => "https://remote.example.com/notes/notags", "content" => "본문" }
    result = Post.from_activitypub_object(hash)

    assert_not result.key?(:tag_list)
  end

  # ── federated_url / missing id ──────────────────────────────────────

  test "federated_url mirrors the object id and is nil when id is missing" do
    with_id = Post.from_activitypub_object({ "id" => "https://remote.example.com/notes/c", "content" => "본문" })
    without_id = Post.from_activitypub_object({ "content" => "본문" })

    assert_equal "https://remote.example.com/notes/c", with_id[:federated_url]
    assert_nil without_id[:federated_url]
  end

  # ── no inReplyTo → no reply attributes ──────────────────────────────

  test "an object without inReplyTo carries no reply attributes" do
    result = Post.from_activitypub_object({ "id" => "https://remote.example.com/notes/root", "content" => "원문" })

    assert_not result.key?(:parent_id)
    assert_not result.key?(:article_id)
    assert_not result.key?(:post_type)
  end

  private

  # fedipub가 발행하는 AP id와 같은 경로를 쓴다(config/fedipub.yml의 server_routes_path).
  # 호스트는 앱 호스트로 붙인다: test 환경의 fedipub site_host(localhost)는 앱 호스트와
  # 다르지만, production에서는 둘 다 ruby-news.dev다.
  def published_url(type, id)
    path = Fedipub::Engine.routes.url_helpers.server_published_path(publishable_type: type, id:)
    "https://#{@local_host}#{path}"
  end
end
