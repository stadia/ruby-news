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

  test "GET index lists recent blog posts above tags" do
    get articles_path

    assert_response :success
    assert_select "aside.recent-blog-posts-sidebar + aside.tags-sidebar"
    assert_select "aside.recent-blog-posts-sidebar a[href=?]",
                  user_profile_blog_post_path(username: users(:john).username, slug: posts(:blog_published)), text: /발행된 긴 글/
  end

  test "GET others lists recent blog posts above tags" do
    get others_path

    assert_response :success
    assert_select "aside.recent-blog-posts-sidebar + aside.tags-sidebar"
    assert_select "aside.recent-blog-posts-sidebar a[href=?]",
                  user_profile_blog_post_path(username: users(:john).username, slug: posts(:blog_published)), text: /발행된 긴 글/
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

  test "POST create rejects internal network url without fetching it" do
    sign_in_as(users(:john))

    SafeHttp.stub(:fetch, ->(*) { flunk "내부 주소는 요청하지 않아야 한다" }) do
      assert_no_difference("Article.count") do
        post articles_path, params: { article: { url: "http://169.254.169.254/latest/meta-data" } }
      end
    end

    assert_response :unprocessable_entity
    assert_select "#error_explanation li", text: /URL/
  end

  test "POST create automatically likes the article as the submitting user" do
    user = users(:john)
    response = Struct.new(:body, :status, :headers).new("<html><title>Submitted article</title></html>", 200, {})
    sign_in_as(user)

    SafeHttp.stub(:fetch, ->(*) { response }) do
      assert_difference("Article.count", 1) do
        assert_difference("Like.count", 1) do
          assert_enqueued_with(job: ArticleJob) do
            post articles_path, params: { article: { url: "https://example.com/submitted-by-user" } }
          end
        end
      end
    end

    article = Article.find_by!(url: "https://example.com/submitted-by-user")

    assert_redirected_to article_path(article)
    assert_equal User.first_bot, article.user
    assert user.likes?(article)
    assert_equal 1, article.reload.likers_count
  end

  # 기사 등록은 LLM 비용이 드므로 회원당 시간당 5회로 제한한다(#1059).
  test "POST create is rate limited per user" do
    sign_in_as(users(:john))

    ArticlesController.cache_store.stub(:increment, 6) do
      SafeHttp.stub(:fetch, ->(*) { flunk "한도 초과 요청은 처리하지 않아야 한다" }) do
        assert_no_difference("Article.count") do
          post articles_path, params: { article: { url: "https://example.com/rate-limited" } }
        end
      end
    end

    assert_redirected_to root_path
    assert_equal I18n.t("posts.rate_limit_exceeded"), flash[:alert]
  end

  # 계정을 여러 개 만들어 회원별 한도를 우회해도 시간당 전체 등록 수는 넘지 못한다(#1072 리뷰).
  test "POST create is capped globally across users" do
    sign_in_as(users(:john))
    over_global = ->(key, *, **) { key.include?(":global:") ? ArticlesController::GLOBAL_CREATE_LIMIT + 1 : 1 }

    ArticlesController.cache_store.stub(:increment, over_global) do
      assert_no_difference("Article.count") do
        post articles_path, params: { article: { url: "https://example.com/global-limited" } }
      end
    end

    assert_redirected_to root_path
    assert_equal I18n.t("posts.rate_limit_exceeded"), flash[:alert]
  end

  # 관리자 등록이 전역 카운터를 채우면 일반 회원이 막히므로 카운터 자체를 건드리지 않아야 한다.
  test "POST create by admins skips the rate limit counters" do
    response = Struct.new(:body, :status, :headers).new("<html><title>Admin article</title></html>", 200, {})
    sign_in_as(users(:admin))

    ArticlesController.cache_store.stub(:increment, ->(*, **) { flunk "관리자 요청은 한도 카운터를 올리지 않아야 한다" }) do
      SafeHttp.stub(:fetch, ->(*) { response }) do
        assert_difference("Article.count", 1) do
          post articles_path, params: { article: { url: "https://example.com/admin-submitted" } }
        end
      end
    end
  end

  test "POST create with a duplicate url redirects to the existing article" do
    # url·origin_url 모두 uniqueness 검증이므로 중복 POST는 저장 실패 →
    # Article#duplicate_url? 분기로 빠져 기존 기사로 리다이렉트한다.
    existing = articles(:ruby_article)
    sign_in_as(users(:john))

    assert_no_difference("Article.count") do
      post articles_path, params: { article: { url: existing.url } }
    end

    assert_redirected_to article_path(existing)
    assert_equal I18n.t("articles.create.already_exists"), flash[:notice]
  end

  # 중복이면 요약·임베딩 LLM 비용을 쓰지 않는다.
  test "POST create with a duplicate url neither likes nor enqueues the article job" do
    sign_in_as(users(:john))

    assert_no_difference("Like.count") do
      assert_no_enqueued_jobs(only: ArticleJob) do
        post articles_path, params: { article: { url: articles(:ruby_article).url } }
      end
    end
  end

  # fixture의 url과 origin_url이 달라, 이 url을 제출하면 url만 :taken이다.
  # 어느 기사로 보낼지 단정할 수 없으므로 검증 오류로 다시 보여 준다.
  test "POST create with only the url taken renders the form with errors" do
    sign_in_as(users(:john))

    assert_no_difference("Article.count") do
      post articles_path, params: { article: { url: articles(:unnormalized_url_article).url } }
    end

    assert_response :unprocessable_entity
  end

  # Turbo 폼은 Accept 첫 항목이 turbo-stream이다. respond_to를 걷어낸 뒤에도
  # 검증 실패 화면은 Turbo가 페이지로 그릴 수 있게 text/html이어야 한다.
  test "POST create from a Turbo form renders validation errors as html" do
    sign_in_as(users(:john))

    post articles_path,
      params: { article: { url: articles(:unnormalized_url_article).url } },
      headers: { "Accept" => "text/vnd.turbo-stream.html, text/html, application/xhtml+xml" }

    assert_response :unprocessable_entity
    assert_equal "text/html", response.media_type
  end

  # utm_* 제거 같은 URL 정규화는 검증 이후 before_create에서 일어나므로, 검증은
  # 통과하고 INSERT에서 유니크 인덱스와 충돌한다. 테스트 resolver가 example.com만
  # 풀어 주므로 그 호스트의 기사를 쓴다.
  test "POST create redirects to the existing article when the insert hits the unique index" do
    existing = articles(:similar_article)
    response = Struct.new(:body, :status, :headers).new("<html><title>Normalized article</title></html>", 200, {})
    sign_in_as(users(:john))

    SafeHttp.stub(:fetch, ->(*) { response }) do
      assert_no_difference([ "Article.count", "Like.count" ]) do
        assert_no_enqueued_jobs(only: ArticleJob) do
          post articles_path, params: { article: { url: "#{existing.url}?utm_source=newsletter" } }
        end
      end
    end

    assert_redirected_to article_path(existing)
    assert_equal I18n.t("articles.create.already_exists"), flash[:notice]
  end

  # 대소문자만 다른 URL은 다른 기사로 등록된다. 예전에는 검증만 대소문자를 무시해
  # 기존 기사 조회가 nil이 되어 500이 났다(#1092).
  test "POST create registers a url that differs only in case as a new article" do
    existing = articles(:similar_article)
    response = Struct.new(:body, :status, :headers).new("<html><title>Case variant</title></html>", 200, {})
    case_variant = existing.url.sub("ruby-performance", "Ruby-Performance")
    sign_in_as(users(:john))

    SafeHttp.stub(:fetch, ->(*) { response }) do
      assert_difference("Article.count", 1) do
        post articles_path, params: { article: { url: case_variant } }
      end
    end

    assert_redirected_to article_path(Article.find_by!(url: case_variant))
  end

  # 호스트 표기만 다르면 정규화 뒤 같은 URL이라 INSERT가 유니크 인덱스에 걸린다.
  test "POST create redirects to the existing article when only the host case differs" do
    existing = articles(:similar_article)
    response = Struct.new(:body, :status, :headers).new("<html><title>Host case</title></html>", 200, {})
    sign_in_as(users(:john))

    SafeHttp.stub(:fetch, ->(*) { response }) do
      assert_no_difference("Article.count") do
        post articles_path, params: { article: { url: existing.url.sub("example.com", "EXAMPLE.com") } }
      end
    end

    assert_redirected_to article_path(existing)
  end

  # 삭제된 기사로 보내면 404다. 관리자 삭제·무관 판정을 사용자가 재등록으로 우회하지
  # 못하도록 등록은 막고 이유를 알린다(#1094).
  test "POST create with the url of a discarded article renders the form with an explanation" do
    discarded = articles(:deleted_article)
    sign_in_as(users(:john))

    assert_no_difference([ "Article.count", "Like.count" ]) do
      assert_no_enqueued_jobs(only: ArticleJob) do
        post articles_path, params: { article: { url: discarded.url } }
      end
    end

    assert_response :unprocessable_entity
    assert_select "#error_explanation li", text: "삭제되었거나 등록 대상에서 제외된 글의 URL입니다.", count: 1
  end

  # url은 삭제된 기사와, origin_url은 살아 있는 기사와 겹치면 살아 있는 기사로 보낸다.
  test "POST create prefers the kept article when the url also matches a discarded one" do
    discarded = articles(:deleted_article)
    kept = articles(:similar_article)
    discarded.update_columns(origin_url: "https://example.com/deleted-article-origin")
    kept.update_columns(origin_url: discarded.url)
    sign_in_as(users(:john))

    post articles_path, params: { article: { url: discarded.url } }

    assert_redirected_to article_path(kept)
  end

  # slug 존재 확인과 INSERT 사이에 같은 slug가 들어온 경우. exists?를 false로 고정해 그
  # 경쟁을 재현한다. 접미사를 붙여 한 번 다시 저장한다(#1093).
  test "POST create retries with a suffixed slug when the slug was taken concurrently" do
    taken = articles(:similar_article) # slug: ruby-performance
    response = Struct.new(:body, :status, :headers).new("<html><title>Ruby Performance</title></html>", 200, {})
    sign_in_as(users(:john))

    fetches = 0
    SafeHttp.stub(:fetch, ->(*) { fetches += 1; response }) do
      Article.stub(:exists?, false) do
        assert_difference([ "Article.count", "Like.count" ], 1) do
          assert_enqueued_with(job: ArticleJob) do
            post articles_path, params: { article: { url: "https://example.com/slug-race" } }
          end
        end
      end
    end

    created = Article.find_by!(url: "https://example.com/slug-race")

    assert_redirected_to article_path(created)
    assert_match(/\A#{taken.slug}-\h{8}\z/, created.slug)
    assert_equal 1, fetches
  end

  test "POST create prefers kept candidates with the fixture roles reversed" do
    first, second = [ articles(:deleted_article), articles(:similar_article) ].sort_by(&:id)
    first.update_columns(deleted_at: Time.current, url: "https://example.com/reversed", origin_url: "https://example.com/reversed-origin")
    second.update_columns(deleted_at: nil, origin_url: first.url)
    sign_in_as(users(:john))
    post articles_path, params: { article: { url: first.url } }

    assert_redirected_to article_path(second)
  end

  test "POST create partial origin collision hides the internal field name" do
    existing = articles(:similar_article)
    existing.update_columns(origin_url: "https://example.com/only-origin")
    sign_in_as(users(:john))
    post articles_path, params: { article: { url: existing.origin_url } }

    assert_response :unprocessable_entity
    assert_select "#error_explanation li", text: "이 URL과 겹치는 등록 정보가 있습니다. 다른 URL을 확인해 주세요.", count: 1
    assert_select "input[name='article[url]'][value='https://example.com/only-origin']"
  end

  test "POST create restores submitted URL when a normalized article is discarded" do
    sign_in_as(users(:john))
    response = Struct.new(:body, :status, :headers).new("<html><title>Filtered</title></html>", 200, {})
    url = "https://EXAMPLE.com/?utm_source=x"
    SafeHttp.stub(:fetch, ->(*) { response }) do
      post articles_path, params: { article: { url: url } }
    end

    assert_response :unprocessable_entity
    assert_select "input[name='article[url]']" do |inputs|
      assert_equal url, inputs.first["value"]
    end
  end

  test "POST create propagates an unclassified unique violation" do
    sign_in_as(users(:john))
    article = Article.new(url: "https://example.com/unknown", user: User.first_bot)
    article.stub(:save, -> { raise ActiveRecord::RecordNotUnique, "unknown" }) do
      Article.stub(:new, article) do
        assert_raises(ActiveRecord::RecordNotUnique) do
          post articles_path, params: { article: { url: article.url } }
        end
      end
    end
  end

  test "POST create automatically discarded article returns 422 without likes or jobs" do
    sign_in_as(users(:john))
    response = Struct.new(:body, :status, :headers).new("<html><title>Show HN: Demo</title></html>", 200, {})

    SafeHttp.stub(:fetch, ->(*) { response }) do
      assert_no_difference("Like.count") do
        assert_no_enqueued_jobs(only: ArticleJob) do
          post articles_path, params: { article: { url: "https://example.com/filtered" } }
        end
      end
    end
    assert_response :unprocessable_entity
    assert_select "form[action='#{articles_path}'][method='post']", count: 1
    assert_select "input[name='_method']", count: 0
    assert_select "#error_explanation li", text: "삭제되었거나 등록 대상에서 제외된 글의 URL입니다.", count: 1
  end

  test "POST create propagates unique violations after storage" do
    sign_in_as(users(:john))
    response = Struct.new(:body, :status, :headers).new("<html><title>Saved article</title></html>", 200, {})
    SafeHttp.stub(:fetch, ->(*) { response }) do
      ArticleJob.stub(:perform_later, ->(*) { raise ActiveRecord::RecordNotUnique, "job collision" }) do
        assert_raises(ActiveRecord::RecordNotUnique) do
          post articles_path, params: { article: { url: "https://example.com/job-collision" } }
        end
      end
    end
  end

  test "POST create recognized conflict without a candidate renders one retry message" do
    error = begin
      Article.transaction(requires_new: true) do
        articles(:ruby_article).update_columns(url: articles(:similar_article).url)
      end

      flunk "URL 인덱스 위반이 필요하다"
    rescue ActiveRecord::RecordNotUnique => violation
      violation
    end
    url = "https://example.com/vanished-conflict"
    article = Article.new(url: url, origin_url: url, user: User.first_bot)
    sign_in_as(users(:john))
    assert_no_difference("Like.count") do
      assert_no_enqueued_jobs(only: ArticleJob) do
        article.stub(:save, -> { raise error }) do
          Article.stub(:new, article) { post articles_path, params: { article: { url: url } } }
        end
      end
    end
    assert_response :unprocessable_entity
    assert_select "#error_explanation li", text: "등록 중 충돌이 발생했습니다. 잠시 후 다시 시도해 주세요.", count: 1
  end

  test "POST create propagates a unique violation while liking the saved article" do
    sign_in_as(users(:john))
    response = Struct.new(:body, :status, :headers).new("<html><title>Saved article</title></html>", 200, {})
    SafeHttp.stub(:fetch, ->(*) { response }) do
      Like.stub(:create_or_find_by!, ->(**) { raise ActiveRecord::RecordNotUnique, "like collision" }) do
        assert_raises(ActiveRecord::RecordNotUnique) do
          post articles_path, params: { article: { url: "https://example.com/like-collision" } }
        end
      end
    end
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
