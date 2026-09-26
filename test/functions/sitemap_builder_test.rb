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

  test "build는 공개 블로그 URL을 한국어 호스트에만 한 번 등재하고 기존 기사를 유지한다" do
    blog = posts(:blog_published)
    article = articles(:ruby_article)
    article.update!(summary_key_ja: [ "要点" ])
    outputs = {}
    capture = ->(locale, host, entries) {
      dsl = FakeDsl.new
      SitemapBuilder.populate(dsl, locale, host, entries)
      outputs[locale] = dsl.calls
    }

    SitemapBuilder.stub(:build_locale, capture) { SitemapBuilder.build }
    path = Rails.application.routes.url_helpers.user_profile_blog_post_path(username: blog.user.username, slug: blog.slug)

    assert_equal 1, outputs.fetch("ko").count { |entry_path, _| entry_path == path }
    refute_includes outputs.fetch("ja").map(&:first), path
    %w[ko ja].each do |locale|
      assert_includes outputs.fetch(locale).map(&:first), "/articles/#{article.slug}"
      assert_includes outputs.fetch(locale).map(&:first), "/"
      assert_equal [ SitemapBuilder::HREFLANG_HOSTS.fetch(locale) ], outputs.fetch(locale).map { |_, options| options[:host] }.uniq
    end
  end

  test "실제 gzip 사이트맵에도 블로그 URL과 lastmod가 한국어 호스트로 저장된다" do
    blog = posts(:blog_published)
    path = Rails.application.routes.url_helpers.user_profile_blog_post_path(username: blog.user.username, slug: blog.slug)
    factory = SitemapGenerator::LinkSet.method(:new)
    Dir.mktmpdir("blog-sitemap") do |directory|
      SitemapGenerator::LinkSet.stub(:new, ->(**options) { factory.call(**options, public_path: directory) }) do
        capture_io { SitemapBuilder.build }
      end

      documents = %w[ko ja].to_h do |locale|
        urls = Dir.glob("#{directory}/sitemaps/#{locale}/*.xml.gz").flat_map do |file|
          xml = Zlib::GzipReader.open(file, &:read)
          Nokogiri::XML(xml).xpath("//*[local-name()='url']")
        end
        [ locale, urls ]
      end
      matches = documents.fetch("ko").select { |url| url.at_xpath("*[local-name()='loc']").text == "https://ruby-news.dev#{path}" }

      assert_equal 1, matches.size
      assert_equal SitemapBuilder.lastmod_for(blog), matches.first.at_xpath("*[local-name()='lastmod']").text
      refute documents.fetch("ja").any? { |url| url.at_xpath("*[local-name()='loc']").text.include?("/blog/") }
      assert_not_empty documents.fetch("ja")
    end
  end

  test "collect_blog_entries는 발행된 미삭제 글과 실제 작성자만 수집한다" do
    kept = posts(:blog_published)
    deleted = create_blog(slug: "deleted-blog")
    deleted.discard!
    remote = create_blog(slug: "remote-blog")
    remote.update_columns(user_id: nil, fedipub_actor_id: fedipub_actors(:john_actor).id)
    entries = SitemapBuilder.collect_blog_entries

    assert_equal [ "/@#{kept.user.username}/blog/#{kept.slug}" ], entries.map(&:path)
    assert_equal [ "ko" ], entries.first.available
    refute entries.any? { |entry| entry.path.include?(posts(:blog_draft).slug) }
  end

  test "collect_blog_entries는 현재 저장된 다국어 slug와 username으로 경로를 생성한다" do
    blog = posts(:blog_published)
    blog.update_columns(slug: "Railsの設計-입문")
    blog.user.update!(username: "new.author")
    entry = SitemapBuilder.collect_blog_entries.first
    params = Rails.application.routes.recognize_path(entry.path, method: :get)

    assert_equal "blogs", params[:controller]
    assert_equal "show", params[:action]
    assert_equal "new.author", params[:username]
    # recognize_path는 UTF-8 경로의 디코딩 결과를 바이너리 문자열로 돌려준다.
    assert_equal blog.slug.b, params[:slug].b
  end

  test "collect_blog_entries는 빈 값과 잘못된 경로 조각을 제외한다" do
    blog = posts(:blog_published)
    [ nil, "", "bad/slug", ".", ".." ].each do |slug|
      blog.update_columns(slug:)

      assert_empty SitemapBuilder.collect_blog_entries, "invalid slug: #{slug.inspect}"
    end

    blog.update_columns(slug: "valid-blog")
    [ "", "bad/name" ].each do |username|
      blog.user.update_columns(username:)

      assert_empty SitemapBuilder.collect_blog_entries, "invalid username: #{username.inspect}"
    end
  end

  test "유효한 점으로 된 username은 @ 접두사가 있으므로 상대 경로로 제외하지 않는다" do
    blog = posts(:blog_published)
    blog.user.update!(username: "..")

    assert_equal [ "/@../blog/#{blog.slug}" ], SitemapBuilder.collect_blog_entries.map(&:path)
  end

  test "블로그 lastmod는 발행과 변경의 최신 유효 시각을 다음 수집에 반영한다" do
    travel_to Time.zone.local(2026, 9, 26, 12) do
      blog = posts(:blog_published)
      published_at = 2.days.ago
      blog.update_columns(published_at:, updated_at: 1.day.ago)

      assert_equal 1.day.ago.iso8601, SitemapBuilder.collect_blog_entries.first.lastmod

      blog.update_columns(updated_at: Time.current)

      assert_equal Time.current.iso8601, SitemapBuilder.collect_blog_entries.first.lastmod

      blog.update_columns(updated_at: 1.day.from_now)

      assert_equal published_at.iso8601, SitemapBuilder.collect_blog_entries.first.lastmod

      blog.update_columns(published_at: Time.zone.local(1935, 1, 1), updated_at: 1.day.from_now)

      assert_nil SitemapBuilder.collect_blog_entries.first.lastmod
    end
  end

  test "collect_blog_entries는 필요한 컬럼만 조인해 N+1 없이 조회한다" do
    create_blog(slug: "second-blog", user: users(:jane))
    queries = []
    callback = ->(*, payload) { queries << payload[:sql] if payload[:sql].match?(/SELECT.*"posts"/i) }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      SitemapBuilder.collect_blog_entries
    end

    assert_equal 1, queries.size
    assert_match(/username/, queries.first)
    assert_no_match(/"(?:posts|users)"\.\*|"body"|"title"|"metadata"/, queries.first)
  end

  private

  def create_blog(slug:, user: users(:john))
    Post.create!(user:, slug:, title: "サイトマップ用ブログ", body: "<p>公開本文</p>",
                 post_type: :blog, status: :published, published_at: 1.day.ago)
  end
end

class SitemapBlogUrlTest < ActionDispatch::IntegrationTest
  test "사이트맵이 생성한 다국어 블로그 경로는 비회원에게 공개된다" do
    blog = posts(:blog_published)
    blog.update_columns(slug: "Rails-레이어-설계")
    entry = SitemapBuilder.collect_blog_entries.first

    get entry.path

    assert_response :success
    assert_includes response.body, blog.title
  end
end
