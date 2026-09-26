# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "zlib"

class SitemapBuilderTest < ActiveSupport::TestCase
  # add(path, options) 호출을 기록하는 테스트용 DSL 스텁.
  class FakeDsl
    attr_reader :calls

    def initialize
      @calls = []
    end

    def add(path, options)
      @calls << [ path, options ]
    end
  end

  test "build는 도메인별로 자기 완결 LinkSet을 생성한다(.dev=ko, .jp=ja)" do
    captured = []
    fake_link_set = Object.new
    def fake_link_set.create(*); end # 블록 미실행: DB/인터프리터 우회

    SitemapGenerator::LinkSet.stub(:new, ->(**opts) { captured << opts; fake_link_set }) do
      SitemapBuilder.build
    end

    assert_equal 2, captured.size, "로케일(ko/ja)마다 LinkSet이 하나씩 생성되어야 한다"

    ko, ja = captured

    assert_equal "https://ruby-news.dev", ko[:default_host]
    assert_equal "sitemaps/ko/", ko[:sitemaps_path]
    assert_equal "https://ruby-news.jp", ja[:default_host]
    assert_equal "sitemaps/ja/", ja[:sitemaps_path]

    captured.each do |opts|
      assert_equal SitemapBuilder::MAX_SITEMAP_LINKS, opts[:max_sitemap_links]
      assert opts[:compress]
      refute opts[:include_root]
    end
  end

  test "populate(ko)는 정적 페이지를 .dev 호스트로 등재한다" do
    dsl = FakeDsl.new
    SitemapBuilder.populate(dsl, "ko", "https://ruby-news.dev", [])

    root = dsl.calls.find { |path, _options| path == "/" }

    assert root, "홈 URL이 등재되어야 한다"
    assert_equal "https://ruby-news.dev", root[1].fetch(:host)
  end

  test "populate(ja)의 <loc>는 .jp 호스트만 가진다" do
    dsl = FakeDsl.new
    SitemapBuilder.populate(dsl, "ja", "https://ruby-news.jp", [])

    hosts = dsl.calls.map { |_path, options| options.fetch(:host) }.uniq

    assert_equal [ "https://ruby-news.jp" ], hosts, "ja 사이트맵의 <loc>는 .jp 호스트만 가진다"
  end

  test "populate는 해당 로케일 번역이 있는 Entry만 등재한다" do
    ko_only = SitemapBuilder::Entry.new(
      path: "/articles/x",
      lastmod: "2026-01-01T00:00:00+09:00",
      available: [ "ko" ]
    )

    ko_dsl = FakeDsl.new
    SitemapBuilder.populate(ko_dsl, "ko", "https://ruby-news.dev", [ ko_only ])

    assert_includes ko_dsl.calls.map(&:first), "/articles/x", "ko 번역이 있으면 ko 사이트맵에 등재"

    ja_dsl = FakeDsl.new
    SitemapBuilder.populate(ja_dsl, "ja", "https://ruby-news.jp", [ ko_only ])

    refute_includes ja_dsl.calls.map(&:first), "/articles/x", "ja 번역이 없으면 ja 사이트맵에서 제외"
  end

  test "lastmod는 발행 이후 업데이트 시각을 반영한다" do
    article = Article.new(
      published_at: Time.zone.local(2026, 1, 1, 10, 0, 0),
      updated_at: Time.zone.local(2026, 1, 2, 10, 0, 0)
    )

    assert_equal "2026-01-02T10:00:00+09:00", SitemapBuilder.lastmod_for(article)
  end

  test "lastmod는 비현실적인 published_at 대신 안전한 updated_at을 사용한다" do
    article = Article.new(
      published_at: Time.zone.local(1935, 1, 1, 10, 0, 0),
      updated_at: Time.zone.local(2026, 1, 2, 10, 0, 0)
    )

    assert_equal "2026-01-02T10:00:00+09:00", SitemapBuilder.lastmod_for(article)
  end

  test "lastmod는 미래 시각을 제외한다" do
    article = Article.new(
      published_at: 1.day.from_now,
      updated_at: Time.zone.local(2026, 1, 2, 10, 0, 0)
    )

    assert_equal "2026-01-02T10:00:00+09:00", SitemapBuilder.lastmod_for(article)
  end

  test "collect_article_entries는 게시 가능한 기사를 번역 로케일과 함께 수집한다" do
    article = articles(:ruby_article)
    article.update!(summary_key_ja: [ "要点" ])

    entry = SitemapBuilder.collect_article_entries.find { |e| e.path == "/articles/#{article.slug}" }

    assert_not_nil entry
    assert_equal %w[ko ja], entry.available
    assert_equal SitemapBuilder.lastmod_for(article.reload), entry.lastmod
  end

  # 매시 전체 기사를 순회하므로 본문·임베딩 같은 TOAST 컬럼을 읽지 않아야 한다.
  test "collect_article_entries는 사이트맵에 필요한 컬럼만 조회한다" do
    queries = []
    callback = ->(*, payload) { queries << payload[:sql] if payload[:sql].include?("articles") }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      SitemapBuilder.collect_article_entries
    end

    assert_not_empty queries
    queries.each do |sql|
      assert_no_match(/"articles"\.\*|embedding|"body"|summary_body/, sql)
    end
  end

  test "실제 gzip 사이트맵은 블로그를 한국어 호스트에만 한 번 등재하고 기존 기사를 유지한다" do
    blog = posts(:blog_published)
    article = articles(:ruby_article)
    article.update!(summary_key_ja: [ "要点" ])
    factory = SitemapGenerator::LinkSet.method(:new)
    Dir.mktmpdir("blog-sitemap") do |directory|
      SitemapGenerator::LinkSet.stub(:new, ->(**options) { factory.call(**options, public_path: directory) }) do
        capture_io { SitemapBuilder.build }
      end

      urls = %w[ko ja].to_h do |locale|
        nodes = Dir.glob("#{directory}/sitemaps/#{locale}/*.xml.gz").flat_map do |file|
          Nokogiri::XML(Zlib::GzipReader.open(file, &:read)).xpath("//*[local-name()='url']")
        end
        [ locale, nodes.map { |url| [ url.at_xpath("*[local-name()='loc']").text, url.at_xpath("*[local-name()='lastmod']")&.text ] } ]
      end
      ko_host = SitemapBuilder::HREFLANG_HOSTS.fetch("ko")
      blog_locs = urls.fetch("ko").select { |loc, _| loc == "#{ko_host}#{blog_path(blog)}" }

      assert_equal [ [ "#{ko_host}#{blog_path(blog)}", SitemapBuilder.lastmod_for(blog) ] ], blog_locs
      refute urls.fetch("ja").any? { |loc, _| loc.include?("/blog/") }
      %w[ko ja].each do |locale|
        host = SitemapBuilder::HREFLANG_HOSTS.fetch(locale)
        locs = urls.fetch(locale).map(&:first)

        assert_includes locs, "#{host}/articles/#{article.slug}"
        assert_equal [ URI(host).host ], locs.map { |loc| URI(loc).host }.uniq, "#{locale} 사이트맵은 자기 호스트만 담아야 한다"
      end
    end
  end

  test "collect_blog_entries는 발행된 미삭제 글과 실제 작성자만 수집한다" do
    kept = posts(:blog_published)
    deleted = create_blog(slug: "deleted-blog")
    deleted.discard!
    remote = create_blog(slug: "remote-blog")
    remote.update_columns(user_id: nil, fedipub_actor_id: fedipub_actors(:john_actor).id)
    entries = SitemapBuilder.collect_blog_entries
    paths = entries.map(&:path)

    assert_includes paths, blog_path(kept)
    assert_equal [ "ko" ], entries.find { |entry| entry.path == blog_path(kept) }.available
    [ deleted.slug, remote.slug, posts(:blog_draft).slug ].each do |slug|
      refute paths.any? { |path| path.end_with?("/blog/#{slug}") }, "제외 대상: #{slug}"
    end
  end

  test "collect_blog_entries가 만든 모든 경로는 blogs#show로 라우팅된다" do
    blog = posts(:blog_published)
    blog.update_columns(slug: "Railsの設計-입문")
    blog.user.update!(username: "new.author")
    [ "a?b", "100%", "c+d#e" ].each { |slug| create_blog(slug:, user: users(:jane)) }
    entries = SitemapBuilder.collect_blog_entries

    assert_includes entries.map(&:path), blog_path(blog.reload)
    assert_equal 4, entries.count { |entry| entry.path.include?("/blog/") }
    entries.each do |entry|
      params = Rails.application.routes.recognize_path(entry.path, method: :get)

      assert_equal [ "blogs", "show" ], params.values_at(:controller, :action), entry.path
    end
    # recognize_path만 UTF-8 디코딩 결과를 바이너리 문자열로 돌려주므로 .b로 비교한다
    # (실제 요청의 params는 UTF-8이다. SitemapBlogUrlTest 참고).
    params = Rails.application.routes.recognize_path(blog_path(blog), method: :get)

    assert_equal "new.author", params[:username]
    assert_equal blog.slug.b, params[:slug].b
  end

  test "collect_blog_entries는 라우트가 받지 않는 경로 조각을 제외한다" do
    blog = posts(:blog_published)
    others = SitemapBuilder.collect_blog_entries.map(&:path) - [ blog_path(blog) ]
    # slug는 Rails 기본 세그먼트 규칙이라 "."도 받지 않는다(v1.0 → RoutingError).
    [ nil, "", "bad/slug", ".", "..", "v1.0-release" ].each do |slug|
      blog.update_columns(slug:)

      assert_equal others, SitemapBuilder.collect_blog_entries.map(&:path), "invalid slug: #{slug.inspect}"
    end

    blog.update_columns(slug: "valid-blog")
    [ "", "bad/name" ].each do |username|
      blog.user.update_columns(username:)

      assert_equal others, SitemapBuilder.collect_blog_entries.map(&:path), "invalid username: #{username.inspect}"
    end
  end

  test "점으로 된 username은 @ 접두사가 있어 상대 경로가 아니므로 수집한다" do
    blog = posts(:blog_published)
    blog.user.update!(username: "..")

    assert_includes SitemapBuilder.collect_blog_entries.map(&:path), "/@../blog/#{blog.slug}"
  end

  test "블로그 lastmod는 수집 시점의 발행·변경 시각 중 최신 유효값이다" do
    travel_to Time.zone.local(2026, 9, 26, 12) do
      blog = posts(:blog_published)
      published_at = 2.days.ago
      blog.update_columns(published_at:, updated_at: 1.day.ago)

      assert_equal 1.day.ago.iso8601, blog_entry(blog).lastmod

      blog.update_columns(updated_at: 1.day.from_now)

      assert_equal published_at.iso8601, blog_entry(blog).lastmod
    end
  end

  test "collect_blog_entries는 배치 경계를 넘어도 모든 글을 한 번씩 수집한다" do
    create_blog(slug: "batch-two", user: users(:jane))
    create_blog(slug: "batch-three")
    expected = SitemapBuilder.collect_blog_entries.map(&:path)

    assert_operator expected.size, :>=, 3
    assert_equal expected, SitemapBuilder.collect_blog_entries(batch_size: 1).map(&:path)
  end

  test "collect_blog_entries는 작성자별 추가 쿼리 없이 필요한 컬럼만 조회한다" do
    create_blog(slug: "second-blog", user: users(:jane))
    queries = []
    callback = ->(*, payload) { queries << payload[:sql] if payload[:sql].start_with?("SELECT") }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      SitemapBuilder.collect_blog_entries
    end

    assert_equal 1, queries.size, queries.join("\n")
    assert_match(/"users"\."username"/, queries.first)
    assert_no_match(/"(?:posts|users)"\.\*|"body"|"title"|"metadata"/, queries.first)
  end

  private

  def create_blog(slug:, user: users(:john))
    Post.create!(user:, slug:, title: "サイトマップ用ブログ", body: "<p>公開本文</p>",
                 post_type: :blog, status: :published, published_at: 1.day.ago)
  end

  def blog_path(post)
    Rails.application.routes.url_helpers.user_profile_blog_post_path(username: post.user.username, slug: post.slug)
  end

  def blog_entry(post)
    SitemapBuilder.collect_blog_entries.find { |entry| entry.path == blog_path(post) }
  end
end

class SitemapBlogUrlTest < ActionDispatch::IntegrationTest
  test "사이트맵이 생성한 다국어 블로그 경로는 비회원에게 공개된다" do
    blog = posts(:blog_published)
    blog.update_columns(slug: "Rails-레이어-설계")
    path = Rails.application.routes.url_helpers.user_profile_blog_post_path(username: blog.user.username, slug: blog.slug)

    assert_includes SitemapBuilder.collect_blog_entries.map(&:path), path

    get path

    assert_response :success
    assert_includes response.body, blog.title
  end
end
