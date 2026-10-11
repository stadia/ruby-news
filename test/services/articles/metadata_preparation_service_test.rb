# frozen_string_literal: true

require "test_helper"

module Articles
  class MetadataPreparationServiceTest < ActiveSupport::TestCase
    Response = Struct.new(:body, :status, :headers)
    Video = Struct.new(:published_at, :title)

    test "서비스는 OperationService를 상속한다" do
      service = MetadataPreparationService.new

      assert_kind_of OperationService, service
    end

    test "url_to_published_at은 mailto 같은 opaque URI에서 크래시 없이 nil을 반환한다" do
      assert_nothing_raised do
        assert_nil Articles::MetadataPreparation.url_to_published_at("mailto:someone@example.com")
      end
    end

    test "트래킹 파라미터를 제거하면서 중복 쿼리 파라미터는 보존한다" do
      article = Article.new(url: "https://example.com/post?tag=ruby&utm_source=x&tag=rails", title: "Existing Title")
      response = Response.new("<html></html>", 200, {})

      SafeHttp.stub(:fetch, ->(*) { response }) do
        result = MetadataPreparationService.new.call(article)

        assert_predicate result, :success?
        assert_equal "https://example.com/post?tag=ruby&tag=rails", article.url
        assert_equal "example.com", article.host
      end
    end

    test "유튜브 URL에서는 재생 위치 파라미터를 제거하고 is_youtube를 설정한다" do
      article = Article.new(url: "https://youtube.com/watch?v=test123&t=30s&feature=share")
      response = Response.new("", 200, {})
      video = Video.new(1.day.ago, "Video title")

      SafeHttp.stub(:fetch, ->(*) { response }) do
        stub_constructor(Yt::Video, ->(*, **) { video }) do
          result = MetadataPreparationService.new.call(article)

          assert_predicate result, :success?
          assert_equal "https://youtube.com/watch?v=test123", article.url
          assert article.is_youtube
          assert_equal "Video title", article.title
        end
      end
    end

    test "경로가 짧은 일반 URL은 discard하고 유튜브 URL은 유지한다" do
      response = Response.new("<html></html>", 200, {})
      article = Article.new(url: "https://example.com", origin_url: "https://example.com", title: "Existing Title")
      youtube_article = Article.new(url: "https://www.youtube.com", origin_url: "https://www.youtube.com")
      video = Video.new(1.day.ago, "YouTube title")

      SafeHttp.stub(:fetch, ->(*) { response }) do
        stub_constructor(Yt::Video, ->(*, **) { video }) do
          service = MetadataPreparationService.new
          service.call(article)
          service.call(youtube_article)
        end
      end

      assert_not_nil article.deleted_at
      assert youtube_article.is_youtube
      assert_nil youtube_article.deleted_at
    end

    test "fetch 실패 시 failure를 반환해도 URL 정규화는 먼저 적용한다" do
      article = Article.new(url: "https://example.com/error-test?utm_source=x&utm_medium=y&ref=z")

      SafeHttp.stub(:fetch, ->(*) { raise Faraday::ConnectionFailed.new("Connection failed") }) do
        result = MetadataPreparationService.new.call(article)

        assert_predicate result, :failure?
        assert_equal :fetch_failed, result.failure
        assert_equal "https://example.com/error-test", article.url
        assert_equal "example.com", article.host
      end
    end

    test "YouTube API 오류를 정상적으로 처리해야 한다" do
      article = Article.new(
        url: "https://www.youtube.com/watch?v=invalid_video_id",
        is_youtube: true
      )
      response = Response.new("", 200, {})

      SafeHttp.stub(:fetch, ->(*) { response }) do
        stub_constructor(Yt::Video, ->(*, **) { raise Yt::Error.new("boom") }) do
          assert_nothing_raised do
            result = MetadataPreparationService.new.call(article)

            assert_predicate result, :failure?
            assert_equal :api_error, result.failure
          end
        end
      end
    end

    test "기존 published_at이 있으면 유지한다" do
      existing_time = 2.days.ago
      article = Article.new(
        url: "https://example.com/2024/01/15/post",
        title: "Existing Title",
        published_at: existing_time
      )
      response = Response.new("<html><head><title>Title</title></head><body>Body</body></html>", 200, {})

      SafeHttp.stub(:fetch, ->(*) { response }) do
        result = MetadataPreparationService.new.call(article)

        assert_predicate result, :success?
        assert_equal existing_time.to_i, article.published_at.to_i
      end
    end

    test "미래 날짜가 추출되면 현재 시각으로 보정한다" do
      future_year = 2.years.from_now.year
      article = Article.new(url: "https://example.com/#{future_year}/01/15/post", title: "Existing Title")
      response = Response.new("<html><head><title>Title</title></head><body>Body</body></html>", 200, {})

      travel_to Time.zone.parse("2026-03-27 12:00:00") do
        SafeHttp.stub(:fetch, ->(*) { response }) do
          result = MetadataPreparationService.new.call(article)

          assert_predicate result, :success?
          assert_equal Time.zone.now.to_i, article.published_at.to_i
        end
      end
    end

    test "meta published_time에서 발행일을 추출한다" do
      article = Article.new(url: "https://example.com/post", title: "Existing Title")
      response = Response.new(
        '<html><head><meta property="article:published_time" content="2026-03-20T10:30:00+09:00"></head><body>Body</body></html>',
        200,
        {}
      )

      SafeHttp.stub(:fetch, ->(*) { response }) do
        result = MetadataPreparationService.new.call(article)

        assert_predicate result, :success?
        assert_equal Time.zone.parse("2026-03-20 10:30:00 +09:00").to_i, article.published_at.to_i
      end
    end

    test "json ld 의 datePublished에서 발행일을 추출한다" do
      article = Article.new(url: "https://example.com/post", title: "Existing Title")
      response = Response.new(
        <<~HTML,
          <html>
            <head>
              <script type="application/ld+json">
                {
                  "@context": "https://schema.org",
                  "@type": "NewsArticle",
                  "datePublished": "2026-03-18T09:15:00+09:00"
                }
              </script>
            </head>
            <body>Body</body>
          </html>
        HTML
        200,
        {}
      )

      SafeHttp.stub(:fetch, ->(*) { response }) do
        result = MetadataPreparationService.new.call(article)

        assert_predicate result, :success?
        assert_equal Time.zone.parse("2026-03-18 09:15:00 +09:00").to_i, article.published_at.to_i
      end
    end

    test "한글 날짜 텍스트에서 발행일을 추출한다" do
      article = Article.new(url: "https://example.com/post", title: "Existing Title")
      response = Response.new(
        '<html><head><title>Title</title></head><body><div class="published-at">2026년 3월 17일</div></body></html>',
        200,
        {}
      )

      SafeHttp.stub(:fetch, ->(*) { response }) do
        result = MetadataPreparationService.new.call(article)

        assert_predicate result, :success?
        assert_equal Date.new(2026, 3, 17), article.published_at.to_date
      end
    end

    test "내부망 주소는 요청하지 않고 blocked_url로 실패한다" do
      article = Article.new(url: "http://192.168.1.150/admin/page")

      SafeHttp.stub(:fetch, ->(*) { flunk "내부 주소는 요청하지 않아야 한다" }) do
        result = MetadataPreparationService.new.call(article)

        assert_equal :blocked_url, result.failure
      end
    end

    test "내부망 주소로 리다이렉트되면 따라가지 않고 blocked_url로 실패한다" do
      article = Article.new(url: "https://example.com/redirect-me")
      requested = []
      redirect = Response.new("", 302, { "location" => "http://10.0.0.5/secret" })

      SafeHttp.stub(:fetch, ->(url, *) { requested << url && redirect }) do
        result = MetadataPreparationService.new.call(article)

        assert_equal :blocked_url, result.failure
      end
      assert_equal [ "https://example.com/redirect-me" ], requested
    end

    # 리다이렉트 규칙 자체는 SafeHttp.get_following_redirects 테스트가 고정한다. 여기서는 최종 URL 반영만 본다.
    test "리다이렉트를 따라간 최종 URL을 기사 URL로 쓴다" do
      article = Article.new(url: "https://example.com/original-post", title: "Existing Title")
      responses = [
        Response.new("", 301, { "location" => "/moved/post-2026" }),
        Response.new("<html></html>", 200, {})
      ]

      SafeHttp.stub(:fetch, ->(*) { responses.shift }) do
        assert_predicate MetadataPreparationService.new.call(article), :success?
      end
      assert_equal "https://example.com/moved/post-2026", article.url
    end

    test "normalized_url은 유튜브와 일반 URL에서 추적 파라미터를 제거한다" do
      parsed = URI.parse("https://example.com/post?tag=ruby&utm_source=x&ref=y")
      youtube = URI.parse("https://youtube.com/watch?v=test123&t=30s&feature=share&si=abc")

      assert_equal "https://example.com/post?tag=ruby", MetadataPreparation.normalized_url(parsed)
      assert_equal "https://youtube.com/watch?v=test123", MetadataPreparation.normalized_url(youtube)
    end

    test "should_discard_url?은 짧은 경로와 ignore URL을 처리한다" do
      short_article = Article.new(url: "https://example.com", is_youtube: false)
      safe_article = Article.new(url: "https://youtube.com/watch?v=test123", is_youtube: true)

      assert MetadataPreparation.should_discard_url?(short_article, URI.parse("https://example.com"))
      assert MetadataPreparation.should_discard_url?(safe_article, URI.parse("https://github.com/rails/rails"))
      assert_not MetadataPreparation.should_discard_url?(safe_article, URI.parse("https://youtube.com/watch?v=test123"))
    end

    test "normalize_published_at은 nil과 미래 시간을 현재 시각으로 보정한다" do
      travel_to Time.zone.parse("2026-05-04 12:00:00") do
        now = Time.zone.now

        assert_equal now.to_i, MetadataPreparation.normalize_published_at(nil).to_i
        assert_equal now.to_i, MetadataPreparation.normalize_published_at(1.day.from_now).to_i
        assert_equal 1.day.ago.to_i, MetadataPreparation.normalize_published_at(1.day.ago).to_i
      end
    end

    test "build_slug는 제목이 없으면 랜덤 slug를 반환한다" do
      slug = MetadataPreparation.build_slug(nil)

      assert_match(/\A\d{8}-[0-9a-f]{8}\z/, slug)
    end

    test "extract_published_at_from_content는 잘못된 HTML에서도 nil을 반환한다" do
      Nokogiri.stub(:HTML, ->(*) { raise StandardError, "parse failed" }) do
        assert_nil MetadataPreparation.extract_published_at_from_content("<html></html>")
      end
    end
  end
end
