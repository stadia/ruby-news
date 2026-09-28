# frozen_string_literal: true

require "test_helper"

class ArticlesControllerTest < ActionDispatch::IntegrationTest
  test "Articles::Search exposes the HTML index composition API" do
    assert_respond_to Articles::Search, :index_html
  end

  test "GET index delegates Ruby-News result composition to Articles::Search" do
    calls = []
    original_index_html = Articles::Search.method(:index_html)

    Articles::Search.stub(:index_html, lambda { |**arguments|
      calls << arguments
      original_index_html.call(**arguments)
    }) do
      get articles_path, params: { search: "  Ruby  " }
    end

    assert_response :success
    assert_equal 1, calls.size
    assert_equal "Ruby", calls.first[:search]
    assert_respond_to calls.first[:pagy], :call
  end

  test "GET index defaults to Ruby-News search results" do
    get articles_path

    assert_response :success
    assert_select "[role='tablist']", count: 0
    assert_select "[data-controller='google-search']", count: 0
    assert_select "#articlesList"
    assert_select "script[src*='cse.google.com']", count: 0
  end

  test "GET index renders search tabs only when search has a value" do
    get articles_path, params: { search: "  Ruby  " }

    assert_response :success
    assert_select "[role='tablist']"
    assert_select "a[role='tab'][href='#{articles_path(source: "ruby_news", search: "Ruby")}'][aria-selected='true'][aria-current='page']",
      text: I18n.t("articles.index.tabs.ruby_news")
    assert_select "a[role='tab'][href='#{articles_path(source: "google", search: "Ruby")}'][aria-selected='false']",
      text: I18n.t("articles.index.tabs.google")
    assert_select "[data-controller='google-search']", count: 0
    assert_select "#articlesList"
  end

  test "GET index with Google source renders search mount with correct attributes" do
    get articles_path, params: { source: "google", search: "  Ruby on Rails  " }

    assert_response :success
    assert_select "[data-controller='google-search'][data-google-search-engine-id-value='119e8b7b7b2f64488'][data-google-search-query-value='Ruby on Rails']"
    assert_select "[data-google-search-error-message-value='#{I18n.t("articles.index.google.error")}']"
    assert_select "[data-google-search-target='loading']", text: I18n.t("articles.index.google.loading")
    assert_select "[data-google-search-target='container']"
    assert_select "[data-google-search-target='error'][hidden]"
    assert_select "[data-controller='google-search'] script[src]", count: 0
  end

  test "GET index with Google source shows correct tab state and hides article content" do
    get articles_path, params: { source: "google", search: "  Ruby on Rails  " }

    assert_response :success
    assert_select "a[role='tab'][href='#{articles_path(source: "ruby_news", search: "Ruby on Rails")}'][aria-selected='false']",
      text: I18n.t("articles.index.tabs.ruby_news")
    assert_select "a[role='tab'][href='#{articles_path(source: "google", search: "Ruby on Rails")}'][aria-selected='true'][aria-current='page']",
      text: I18n.t("articles.index.tabs.google")
    assert_select "#articlesList", count: 0
    assert_select "script[type='application/ld+json']", count: 0
  end

  test "GET index ignores Google source when search is blank" do
    get articles_path, params: { source: "google", search: "   " }

    assert_response :success
    assert_select "[role='tablist']", count: 0
    assert_select "[data-controller='google-search']", count: 0
    assert_select "#articlesList"
  end

  test "GET index treats unknown source as Ruby-News" do
    get articles_path, params: { source: "unknown", search: "Ruby" }

    assert_response :success
    assert_select "a[role='tab'][aria-selected='true'][aria-current='page']", text: I18n.t("articles.index.tabs.ruby_news")
    assert_select "[data-controller='google-search']", count: 0
    assert_select "#articlesList"
  end

  test "GET index skips article like and sidebar tag queries for Google source" do
    sql_queries = capture_sql_queries do
      get articles_path, params: { source: "google", search: "Ruby" }
    end

    assert_response :success
    assert_empty sql_queries.grep(/FROM "articles"/)
    assert_empty sql_queries.grep(/FROM "likes"/)
    assert_empty sql_queries.grep(/FROM "tags"/)
  end

  test "GET index preloads liked articles for signed in user" do
    user = users(:john)
    articles = 10.times.map do |index|
      article = Article.new(
        title: "Indexed article #{index}",
        title_ko: "인덱스 기사 #{index}",
        url: "https://example.com/indexed-article-#{index}",
        origin_url: "https://example.com/indexed-article-#{index}",
        host: "example.com",
        slug: "indexed-article-#{index}",
        published_at: (20 - index).days.ago,
        created_at: (20 - index).days.ago,
        is_related: true,
        user: user,
        site: sites(:ruby_weekly)
      )
      article.stub(:generate_metadata, nil) { article.save! }
      article
    end
    article = articles.first
    Like.create!(actor: user.fedipub_actor, likeable: article, created_at: Time.current)
    sign_in_as(user)

    like_queries = capture_like_queries do
      get articles_path
    end

    assert_response :success
    assert_includes @response.body, article.title_ko
    assert_equal 1, like_queries.size
    assert_select "aside.tags-sidebar"
    assert_select "a[href='#{tag_path(tags(:ruby_tag).name)}']", text: /#ruby/
  end

  test "GET others preloads liked articles for signed in user" do
    user = users(:john)
    article = Article.new(
      title: "Other article",
      title_ko: "기타 기사",
      url: "https://example.com/other-article",
      origin_url: "https://example.com/other-article",
      host: "example.com",
      slug: "other-article",
      published_at: 10.days.ago,
      created_at: 10.days.ago,
      is_related: false,
      user: user,
      site: sites(:hn_site)
    )
    article.stub(:generate_metadata, nil) { article.save! }
    Like.create!(actor: user.fedipub_actor, likeable: article, created_at: Time.current)
    sign_in_as(user)

    like_queries = capture_like_queries do
      get others_path
    end

    assert_response :success
    assert_includes @response.body, "Other article"
    assert_equal 1, like_queries.size
    assert_select "aside.tags-sidebar"
    assert_select "a[href='#{tag_path(tags(:rails_tag).name)}']", text: /#rails/
  end

  test "GET tag filters articles by keyword" do
    article = articles(:ruby_article)
    article.tag_list.add("ruby")
    article.save!

    get tag_path("ruby")

    assert_response :success
    assert_select "h1", text: "#ruby"
    assert_select "#articlesList", text: /#{Regexp.escape(article.title_ko)}/
    assert_select "a[href='#{tag_path("ruby")}']", text: /#ruby/
  end

  test "GET tag supports dotted keywords" do
    article = articles(:ruby_article)
    article.tag_list.add("ruby-3.4")
    article.save!

    get tag_path("ruby-3.4")

    assert_response :success
    assert_select "h1", text: "#ruby-3.4"
    assert_select "#articlesList", text: /#{Regexp.escape(article.title_ko)}/
  end

  test "GET show returns 200 with article title" do
    article = articles(:ruby_article)
    get article_path(article)

    assert_response :success
    assert_select "article"
    assert_select "h1", text: /#{Regexp.escape(article.title_ko)}/
  end

  test "GET show exposes article metadata and readable structured data" do
    article = articles(:ruby_article)
    article.tag_list.add("ruby")
    article.save!

    get article_path(article)

    assert_response :success
    assert_select "meta[property='og:type'][content='article']"
    assert_select "meta[name='description'][content='Ruby 3.4의 주요 개선사항']"
    assert_select "meta[property='article:tag'][content='ruby']"
    assert_select "meta[name='robots']", count: 0
    breadcrumbs = structured_data("BreadcrumbList").fetch("itemListElement")

    assert_equal [ "홈", "지난 글들", "Ruby 3.4의 놀라운 새 기능들" ], breadcrumbs.map { |item| item.fetch("name") }
  end

  test "GET show provides article source dates and speakable selectors without a thumbnail" do
    article = articles(:ruby_article)

    get article_path(article)

    schema = structured_data("NewsArticle")

    assert_equal "Ruby 3.4의 놀라운 새 기능들", schema.fetch("headline")
    assert_equal "ko-KR", schema.fetch("inLanguage")
    assert_equal "https://ruby-news.dev", schema.fetch("publisher").fetch("url")
    assert_equal article.url, schema.fetch("translationOfWork").fetch("url")
    assert_equal [ "h1", "#article-detail-body" ], schema.fetch("speakable").fetch("cssSelector")
    assert_equal article.published_at.iso8601, schema.fetch("datePublished")
    assert_equal article.reload.updated_at.iso8601, schema.fetch("dateModified")
    assert_not schema.key?("image")
  end

  test "GET show on Japanese host keeps publisher tied to host when content locale is Korean" do
    host! "ruby-news.jp"
    cookies[:locale] = "ko"

    get article_path(articles(:ruby_article))

    assert_response :success
    schema = structured_data("NewsArticle")

    assert_equal "ko-KR", schema.fetch("inLanguage")
    assert_equal "https://ruby-news.jp", schema.fetch("publisher").fetch("url")
    assert_equal "https://ruby-news.jp", schema.fetch("author").fetch("url")
    assert_select "meta[name='robots']", count: 0
  end

  test "GET show noindexes Japanese fallback until a translated summary exists" do
    article = articles(:ruby_article)
    article.update_columns(title_ja: "Ruby 日本語の見出し", summary_key_ja: nil)
    host! "ruby-news.jp"

    get article_path(article)

    assert_response :success
    assert_select "meta[name='robots'][content='noindex, follow']"
    assert_equal "ja-JP", structured_data("NewsArticle").fetch("inLanguage")

    article.update_columns(summary_key_ja: [ "日本語の要約" ])
    get article_path(article)

    assert_response :success
    assert_select "meta[name='robots']", count: 0
    assert_select "meta[name='description'][content='日本語の要約']"
  end

  test "GET show uses attached thumbnail in Open Graph and article schema" do
    article = articles(:ruby_article)
    article.thumbnail.attach(io: StringIO.new("thumbnail"), filename: "thumbnail.png", content_type: "image/png")

    get article_path(article)

    assert_response :success
    image = structured_data("NewsArticle").fetch("image")

    assert_includes image, "/rails/active_storage/blobs/redirect/"
    assert_includes image, "thumbnail.png"
    assert_select "meta[property='og:image'][content='#{image}']"
  end

  test "GET show omits article schema when its display title is blank" do
    article = articles(:ruby_article)
    article.update_columns(title: "", title_ko: nil, published_at: nil)

    get article_path(article)

    assert_response :success
    assert_nil structured_data("NewsArticle")
    assert_not_nil structured_data("BreadcrumbList")
    assert_select "meta[property='article:published_time']", count: 0
    assert_select "h2", text: I18n.t("articles.show.related_heading"), count: 0
  end

  test "GET show without tags omits Open Graph article tags" do
    article = articles(:site_only_article)

    get article_path(article)

    assert_response :success
    assert_equal "Hacker News에서 본 Ruby 소식", structured_data("NewsArticle").fetch("headline")
    assert_select "meta[property='article:tag']", count: 0
  end

  test "GET show ranks only kept confirmed similar articles and limits results to four" do
    article = articles(:ruby_article)
    embedding = [ 1.0 ] + Array.new(3071, 0.0)
    article.update_columns(embedding: embedding)
    candidates = %i[korean_content_article youtube_ruby_talk site_only_article similar_article one].map.with_index do |fixture, index|
      candidate = articles(fixture)
      candidate.update_columns(title_ko: "유사 기사 #{index}", embedding: [ 1.0, (index + 1) * 0.1 ] + Array.new(3070, 0.0))
      candidate
    end
    articles(:two).update_columns(title_ko: "삭제된 유사 기사", embedding: embedding, deleted_at: Time.current)
    articles(:unnormalized_url_article).update_columns(title_ko: nil, embedding: embedding)

    get article_path(article)

    assert_response :success
    assert_select "h2", text: I18n.t("articles.show.related_heading")
    candidates.first(4).each { |candidate| assert_select "h3", text: candidate.title_ko }
    assert_select "h3", text: candidates.last.title_ko, count: 0
    assert_select "h3", text: article.title_ko, count: 0
    assert_select "h3", text: "삭제된 유사 기사", count: 0
    assert_select "h3", text: articles(:unnormalized_url_article).title, count: 0
  end

  test "GET show rejects discarded articles and unsupported JSON representation" do
    article = articles(:ruby_article)

    get article_path(article, format: :json)

    assert_response :not_acceptable

    article.update_columns(deleted_at: Time.current)
    get article_path(article)

    assert_response :not_found
  end

  test "GET show without summary key items does not render an empty summary box" do
    article = articles(:site_only_article)
    article.update!(summary_key: nil, summary_key_ja: nil)

    get article_path(article)

    assert_response :success
    assert_select "h2", text: I18n.t("articles.show.summary_heading"), count: 0
  end

  test "GET show with .md extension returns markdown representation" do
    article = articles(:ruby_article)
    article.summary_body = "요약된 본문"
    article.summary_key = [ "핵심 요약 1" ]
    article.summary_detail = { "introduction" => "소개", "conclusion" => "결론" }
    article.save!

    get article_path(article, format: :md)

    assert_response :success
    assert_equal "text/markdown; charset=utf-8", response.content_type
    assert_includes response.body, "# #{article.display_title}"
    assert_includes response.body, "- **원문 URL**: #{article.url}"
    assert_includes response.body, "- **Ruby-News URL**: #{Rails.application.routes.url_helpers.article_url(article)}"
    assert_includes response.body, "## 요약"
    assert_includes response.body, "- 핵심 요약 1"
    assert_includes response.body, "요약된 본문"
  end

  test "GET new renders intake form for authenticated user" do
    sign_in_as(users(:john))

    get new_article_path

    assert_response :success
    assert_select "h1", text: "새 글 등록"
    assert_select "form[action='#{articles_path}']"
    assert_select "input[name='article[url]']"
    assert_select "a[href='#{articles_path}']", text: "목록으로 돌아가기"
  end

  test "POST create without url rerenders form with validation errors" do
    sign_in_as(users(:john))

    post articles_path, params: { article: { url: "" } }

    assert_response :unprocessable_entity
    assert_select "#error_explanation"
    assert_select "#error_explanation li", text: /URL/
  end

  test "POST create automatically likes the article as the submitting user" do
    user = users(:john)
    response = Struct.new(:body, :status, :headers).new("<html><title>Submitted article</title></html>", 200, {})
    sign_in_as(user)

    Faraday.stub(:get, ->(*) { response }) do
      assert_difference("Article.count", 1) do
        assert_difference("Like.count", 1) do
          post articles_path, params: { article: { url: "https://example.com/submitted-by-user" } }
        end
      end
    end

    article = Article.find_by!(url: "https://example.com/submitted-by-user")

    assert_redirected_to article_path(article)
    assert_equal User.first_bot, article.user
    assert user.likes?(article)
    assert_equal 1, article.reload.likers_count
  end

  test "POST create with a duplicate url redirects to the existing article" do
    # url·origin_url 모두 uniqueness 검증이므로 중복 POST는 저장 실패 →
    # errors.details.fetch(:origin_url/:url, []).any?(:taken) 분기로 빠져
    # existing_article로 리다이렉트한다(articles_controller.rb:156). 이 분기를
    # 커버하는 테스트가 없으면 fetch 키를 바꿔도 0 failures다.
    existing = articles(:ruby_article)
    sign_in_as(users(:john))

    assert_no_difference("Article.count") do
      post articles_path, params: { article: { url: existing.url } }
    end

    assert_redirected_to article_path(existing)
    assert_equal I18n.t("articles.create.already_exists"), flash[:notice]
  end

  test "GET others renders pagination and push notification modal when multiple pages exist" do
    user = users(:john)

    35.times do |index|
      article = Article.new(
        title: "Paginated article #{index}",
        title_ko: "페이지 기사 #{index}",
        url: "https://example.com/paginated-article-#{index}",
        origin_url: "https://example.com/paginated-article-#{index}",
        host: "example.com",
        slug: "paginated-article-#{index}",
        published_at: (4.days + index.minutes).ago,
        created_at: (4.days + index.minutes).ago,
        is_related: false,
        user: user,
        site: sites(:ruby_weekly)
      )
      article.stub(:generate_metadata, nil) { article.save! }
    end

    Configs::WebPush.stub(:configured?, true) do
      Configs::WebPush.stub(:public_key, "test-public-key") do
        sign_in_as(user)
        get others_path

        assert_response :success
        assert_includes @response.body, "알림 설정"
        assert_includes @response.body, "나중에 하기"
        assert_includes @response.body, "First"
        assert_includes @response.body, "Prev"
        assert_includes @response.body, "Next"
        assert_includes @response.body, "Last"
      end
    end
  end

  private

  def structured_data(type)
    response.parsed_body.css("script[type='application/ld+json']").map { |script| JSON.parse(script.text) }
      .find { |schema| schema["@type"] == type }
  end

  def capture_like_queries
    queries = []
    callback = lambda do |_name, _start, _finish, _id, payload|
      sql = payload[:sql]
      next unless sql&.include?('"likes"')
      next unless payload[:name] != "SCHEMA"

      queries << sql
    end

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      yield
    end

    queries
  end

  def capture_sql_queries
    queries = []
    callback = lambda do |_name, _start, _finish, _id, payload|
      next if payload[:name] == "SCHEMA"

      queries << payload[:sql] if payload[:sql]
    end

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      yield
    end

    queries
  end
end
