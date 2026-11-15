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
    # 모바일 블록에도 같은 사이드바가 있으므로 데스크톱 사이드바로 범위를 좁힌다.
    assert_select ".hidden.lg\\:block aside.recent-blog-posts-sidebar + aside.recent-comments-sidebar"
    assert_select ".hidden.lg\\:block aside.recent-blog-posts-sidebar a[href=?]",
                  user_profile_blog_post_path(username: users(:john).username, slug: posts(:blog_published)),
                  text: /발행된 긴 글/
    assert_select ".hidden.lg\\:block aside.recent-blog-posts-sidebar a[href=?]",
                  user_profile_blog_post_path(username: users(:john).username, slug: posts(:blog_draft)), count: 0
    # 댓글 사이드바와 같은 이름(Post#author_name)을 쓴다.
    assert_select ".hidden.lg\\:block aside.recent-blog-posts-sidebar a[href=?] span",
                  user_profile_blog_path(username: users(:john).username),
                  text: "존 도"
  end

  test "GET root shows blog posts and comments before latest news on mobile, tags only on desktop" do
    get root_path

    assert_response :success
    assert_select ".lg\\:hidden > aside.recent-blog-posts-sidebar + aside.recent-comments-sidebar"
    assert_select "section.mb-8 + .lg\\:hidden + section h2", text: I18n.t("home.index.latest_news")
    assert_select ".lg\\:hidden aside.tags-sidebar", count: 0
    assert_select ".hidden.lg\\:block aside.recent-blog-posts-sidebar + aside.recent-comments-sidebar + aside.tags-sidebar"
    assert_select "aside.tags-sidebar", count: 1
  end

  test "GET root limits mobile comments to one and loads comments once" do
    posts(:root_post).update_columns(post_type: Post.post_types[:comment], article_id: articles(:ruby_article).id, status: Post.statuses[:published])
    queries = capture_queries { get root_path }

    assert_response :success
    assert_select ".lg\\:hidden aside.recent-comments-sidebar .space-y-3 > *", count: 1
    assert_select ".hidden.lg\\:block aside.recent-comments-sidebar .space-y-3 > *", count: 2
    assert_equal 1, queries.grep(/FROM "posts" INNER JOIN "articles"/).size
  end

  test "GET root hides the blog sidebar when no eligible blogs remain" do
    posts(:blog_published).update_columns(user_id: nil)

    get root_path

    assert_response :success
    assert_select "aside.recent-blog-posts-sidebar", count: 0
    assert_select ".lg\\:hidden > aside.recent-comments-sidebar"
  end

  test "GET root loads recent blogs once and preloads multiple authors" do
    [ [ :root_post, :jane ], [ :reply_post, :admin ] ].each do |post_name, user_name|
      posts(post_name).update_columns(user_id: users(user_name).id, post_type: Post.post_types[:blog], title: "추가 블로그", published_at: Time.current)
    end
    queries = capture_queries { get root_path }

    assert_response :success
    assert_select ".hidden.lg\\:block aside.recent-blog-posts-sidebar .group", count: 3
    assert_select ".lg\\:hidden aside.recent-blog-posts-sidebar .group", count: 1
    assert_select ".lg\\:hidden aside.recent-comments-sidebar .space-y-3 > *", count: 1
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

  test "both home hosts show one card per verified episode and keep a separate Marco interview" do
    episode = create_episode_articles
    separate = create_featured_article!(title: "Herb and ReactionView with Marco Roth", title_ko: "Marco Roth 인터뷰", slug: "episode-555", summary_key: [ "요약" ])
    separate.update_columns(url: "https://www.therubyonrailspodcast.com/555", origin_url: "https://www.therubyonrailspodcast.com/555")

    %w[ruby-news.dev ruby-news.jp].each_with_index do |host, index|
      episode.last.update_columns(likers_count: index.zero? ? 100 : 0)
      host! host
      get root_path

      assert_response :success
      assert_select "#feature_article_#{episode.last.id}", count: 1
      episode.first(2).each do |article|
        assert_select "[id='article_#{article.id}'], [id='feature_article_#{article.id}']", count: 0
      end
      assert_select "a[href=?]", article_path(separate), minimum: 1
      episode.each { |article| assert_select "a[href=?]", article.url, count: 1 }
    end

    episode.each do |article|
      get article_path(article)

      assert_response :success
      assert_predicate article.reload, :kept?
    end
  end

  test "latest news deduplicates before filling nine cards" do
    Article.update_all(created_at: 5.days.ago)
    episode = create_episode_articles
    episode.each { |article| article.update_columns(created_at: 3.days.ago) }
    8.times do |i|
      article = create_featured_article!(title: "Other #{i}", title_ko: "별개 기사 #{i}", slug: "other-#{i}", summary_key: [ "요약" ])
      article.update_columns(created_at: 4.days.ago)
    end

    get root_path

    assert_response :success
    assert_select "#articlesList > div", count: 9
    assert_select "#articlesList #article_#{episode.last.id}", count: 1
    episode.first(2).each { |article| assert_select "#article_#{article.id}", count: 0 }
    episode.each { |article| assert_select "#articlesList a[href=?]", article.url, count: 1 }
  end

  test "latest news counts unique episodes before choosing the 24 hour window" do
    Article.update_all(created_at: 5.days.ago)
    episode = create_episode_articles
    7.times do |i|
      create_featured_article!(title: "Recent #{i}", title_ko: "최근 별개 기사 #{i}", slug: "recent-#{i}", summary_key: [ "요약" ])
    end
    old = create_featured_article!(title: "Older", title_ko: "이전 기사", slug: "older", summary_key: [ "요약" ])
    old.update_columns(created_at: 3.days.ago)
    # 주요 뉴스는 48시간 이후에만 빠지므로, 여기서는 주요 뉴스 세 자리를 참여도로 고정한다.
    3.times do |i|
      feature = create_featured_article!(title: "Featured #{i}", title_ko: "주요 기사 #{i}", slug: "featured-#{i}", summary_key: [ "요약" ])
      feature.update_columns(created_at: 30.hours.ago, likers_count: 100)
    end

    get root_path

    assert_response :success
    assert_select "#articlesList > div", count: 9
    assert_select "#articlesList #article_#{episode.last.id}", count: 1
    assert_select "#articlesList #article_#{old.id}", count: 1
  end

  private

  def create_episode_articles
    [
      "https://rubyonrails.org/2026/11/13/on-rails-marco-roth-herb-reaction-view",
      "https://podcast.rubyonrails.org/2462975/episodes/20121188-marco-roth-teaching-rails-to-read-its-own-template",
      "https://www.youtube.com/watch?v=ko60zbx6dOE"
    ].each_with_index.map do |url, i|
      article = create_featured_article!(title: "Marco Roth interview", title_ko: "Marco Roth 인터뷰", slug: "marco-#{i}", summary_key: [ "요약" ])
      article.update_columns(url: url, origin_url: url, created_at: (3 - i).minutes.ago)
      article
    end
  end

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
