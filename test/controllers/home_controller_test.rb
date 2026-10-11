# frozen_string_literal: true

require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  setup do
    @thumbnail_path = Rails.root.join("public/apple-touch-icon.png")
  end

  test "GET root renders successfully" do
    get root_path

    assert_response :success
    assert_select "h1.sr-only", text: /Ruby·Rails 개발자를 위한 한국어 AI 뉴스/
    assert_select "aside.recent-comments-sidebar"
    assert_select "aside.tags-sidebar"
    assert_select "a[href='#{tag_path(tags(:ruby_tag).name)}']", text: /#ruby/
    assert_select "a[href='https://github.com/stadia/ruby-news']", text: /GitHub/
  end

  test "GET root lists recent published blog posts above recent comments" do
    get root_path

    assert_response :success
    assert_select "aside.recent-blog-posts-sidebar + aside.recent-comments-sidebar"
    assert_select "aside.recent-blog-posts-sidebar a[href=?]",
                  user_profile_blog_post_path(username: users(:john).username, slug: posts(:blog_published)),
                  text: /발행된 긴 글/
    assert_select "aside.recent-blog-posts-sidebar a[href=?]",
                  user_profile_blog_post_path(username: users(:john).username, slug: posts(:blog_draft)), count: 0
    # 댓글 사이드바와 같은 이름(Post#author_name)을 쓴다.
    assert_select "aside.recent-blog-posts-sidebar a[href=?] span",
                  user_profile_blog_path(username: users(:john).username),
                  text: "존 도"
  end

  test "GET root hides the blog sidebar when no eligible blogs remain" do
    posts(:blog_published).update_columns(user_id: nil)

    get root_path

    assert_response :success
    assert_select "aside.recent-blog-posts-sidebar", count: 0
  end

  test "GET root loads recent blogs once and preloads multiple authors" do
    [ [ :root_post, :jane ], [ :reply_post, :admin ] ].each do |post_name, user_name|
      posts(post_name).update_columns(user_id: users(user_name).id, post_type: Post.post_types[:blog], title: "추가 블로그", published_at: Time.current)
    end
    queries = capture_queries { get root_path }

    assert_response :success
    assert_select "aside.recent-blog-posts-sidebar .group", count: 3
    assert_equal 1, queries.grep(/FROM "posts".*"posts"\."status" =/).size
    assert_operator queries.grep(/FROM "users" WHERE "users"\."id" =/).size, :<=, 1
    assert_empty queries.grep(/FROM "active_storage_blobs" WHERE "active_storage_blobs"\."id" =/)
    assert_empty queries.grep(/FROM "active_storage_attachments" WHERE "active_storage_attachments"\."record_id" =/)
  end

  test "GET root emits WebSite schema with a SearchAction" do
    # set_web_site_schema(application_controller.rb:35)는 루트 경로에서만 @web_site를
    # 세팅하고, StructuredData는 @web_site가 없으면 조용히 아무것도 그리지 않는다.
    # 이 테스트가 없으면 가드를 뒤집어도 양 스위트가 0 failures다.
    get root_path

    assert_response :success
    assert_select "script[type='application/ld+json']"
    assert_match(/"@type":\s*"WebSite"/, @response.body)
    assert_match(/"@type":\s*"SearchAction"/, @response.body)
    assert_match(/search_term_string/, @response.body)
  end

  test "GET root gives like/boost buttons an accessible name via sr-only text" do
    # 아이콘만 있는 버튼은 스크린리더가 "버튼"으로만 읽는다(button-name). sr-only
    # 텍스트로 접근명을 부여하되, aria-label 대신 sr-only를 써서 보이는 카운트가
    # 접근명에 포함되게 한다(label-content-name-mismatch 회피).
    get root_path

    assert_response :success
    assert_select "button span.sr-only", text: /좋아요/
    assert_select "button span.sr-only", text: /부스트/
    # boost 버튼에 aria-label을 두면 접근명이 카운트를 배제하므로, 부스트 aria용
    # 텍스트는 sr-only로만 노출되어야 한다(카운트 표시 span은 aria-hidden 아님).
    assert_select "form.inline-flex button[aria-label]", false
  end

  test "GET root preloads liked articles for signed in user" do
    user = users(:john)
    Like.create!(actor: user.fedipub_actor, likeable: articles(:ruby_article), created_at: Time.current)
    sign_in_as(user)

    like_queries = capture_like_queries do
      get root_path
    end

    assert_response :success
    assert_equal 1, like_queries.size
  end

  test "GET root avoids per-record queries for thumbnails and recent comment authors" do
    queries = capture_queries do
      get root_path
    end

    assert_response :success
    assert_empty queries.grep(/FROM "active_storage_blobs" WHERE "active_storage_blobs"\."id" =/)
    assert_empty queries.grep(/FROM "active_storage_attachments" WHERE "active_storage_attachments"\."record_id" =/)
    assert_operator queries.grep(/FROM "users" WHERE "users"\."id" =/).size, :<=, 1
  end

  test "GET root renders featured article cards with hero summary string" do
    attach_thumbnail(articles(:ruby_article))
    attach_thumbnail(articles(:korean_content_article))
    attach_thumbnail(create_featured_article!(title: "Feature third", title_ko: "세 번째 주요 기사", slug: "feature-third", summary_key: "핵심 요약"))

    get root_path

    assert_response :success
    assert_select "section", text: /주요 뉴스/
    assert_select "img", minimum: 3
    assert_select "a[href='#{article_path(articles(:ruby_article))}']", text: /Ruby 3.4의 놀라운 새 기능들/
  end

  test "GET root renders featured hero summary array items" do
    attach_thumbnail(articles(:ruby_article))
    attach_thumbnail(articles(:korean_content_article))
    attach_thumbnail(create_featured_article!(
      title: "Array feature",
      title_ko: "배열 요약 주요 기사",
      slug: "array-feature",
      summary_key: [ "첫 번째 요약", "두 번째 요약", "세 번째 요약" ],
      published_at: 1.minute.from_now
    ))

    get root_path

    assert_response :success
    assert_select "li span", text: /첫 번째 요약/
    assert_select "li span", text: /두 번째 요약/
    assert_select "li span", text: /세 번째 요약/
  end

  test "GET about returns 200 with introduction content" do
    get about_path

    assert_response :success
    assert_select "h1", text: /Ruby-News 소개/
  end

  test "GET privacy policy returns 200 with privacy content" do
    get privacy_policy_path

    assert_response :success
    assert_select "h1", text: /개인정보처리방침/
  end

  test "GET terms returns 200 with terms content" do
    get terms_path

    assert_response :success
    assert_select "h1", text: /이용약관/
  end

  # Relation 을 그대로 캐시하면 레코드가 아니라 쿼리가 직렬화된다. 그러면 캐시가
  # 아무것도 아껴주지 못할 뿐 아니라, without_toast 가 굳혀 둔 컬럼 목록이 캐시
  # 수명(1시간) 동안 살아남아 컬럼 리네임 이후 옛 이름으로 질의한다
  # (federails_actor_id -> fedipub_actor_id 리네임 때 /rss 가 500 을 냈다).
  # 이 테스트가 없으면 to_a 를 지워도 양 스위트가 0 failures 다.
  test "GET rss caches loaded records so a cache hit issues no article query" do
    create_featured_article!(
      title: "RSS cache article",
      title_ko: "RSS 캐시 기사",
      slug: "rss-cache-article",
      summary_key: [ "요약" ]
    )

    with_memory_cache do
      get rss_path

      assert_response :success

      cached = Rails.cache.read(Article::RSS_CACHE_KEY)

      refute_kind_of ActiveRecord::Relation, cached,
                     "지연 평가 Relation 이 캐시됐다. 캐시 히트마다 쿼리가 다시 나가고 스키마 변경에 깨진다"
      assert_kind_of Array, cached
      assert_predicate cached, :any?

      sql = capture_article_queries { get rss_path }

      assert_response :success
      assert_empty sql, "캐시 히트인데 articles 를 다시 조회했다: #{sql.inspect}"
    end
  end

  private

  def with_memory_cache
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    yield
  ensure
    Rails.cache = original_cache
  end

  def capture_article_queries(&block)
    statements = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      statements << payload[:sql] if payload[:sql]&.include?('FROM "articles"')
    end
    block.call
    statements
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  def capture_like_queries(&block)
    capture_queries(&block).select { |sql| sql.include?('"likes"') }
  end

  def capture_queries(&block)
    queries = []
    callback = lambda do |_name, _start, _finish, _id, payload|
      sql = payload[:sql]
      next unless sql
      next if payload[:name] == "SCHEMA"

      queries << sql
    end

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      block.call
    end

    queries
  end

  def attach_thumbnail(article)
    article.thumbnail.attach(
      io: File.open(@thumbnail_path),
      filename: "#{article.slug || article.id}.png",
      content_type: "image/png"
    )
  end

  def create_featured_article!(title:, title_ko:, slug:, summary_key:, published_at: Time.current)
    article = Article.new(
      title: title,
      title_ko: title_ko,
      url: "https://example.com/#{slug}",
      origin_url: "https://example.com/#{slug}",
      host: "example.com",
      slug: slug,
      published_at: published_at,
      is_related: true,
      summary_key: summary_key,
      user: users(:john),
      site: sites(:ruby_weekly)
    )

    article.stub(:generate_metadata, nil) { article.save! }
    article
  end
end
