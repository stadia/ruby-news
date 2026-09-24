# frozen_string_literal: true

require "test_helper"

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
end
