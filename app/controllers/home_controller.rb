# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

require "schema_dot_org/news_media_organization"

class HomeController < ApplicationController
  include WebOnlyFormats
  # rss·llms·robots는 각각 RSS XML과 text/plain을 의도적으로 내놓는다.
  skip_before_action :ensure_web_format, only: %i[rss llms robots]

  skip_before_action :authenticate_user!

  # Locale-aware publisher (NewsMediaOrganization) schema — reused in
  # ArticlesController as well. url/logo/masthead 는 현재 호스트 도메인 기준이고
  # same_as 는 양 도메인(.dev/.jp)의 핸들을 모두 포함해 동일 발행 주체임을 표현한다.
  #: (String | Symbol) -> SchemaDotOrg::NewsMediaOrganization
  def self.publisher_schema(locale)
    host = Hosts.for_locale(locale)
    SchemaDotOrg::NewsMediaOrganization.new(
      name:     "Ruby-News",
      url:      host,
      logo:     "#{host}/icon.png",
      same_as:  [
        "https://ruby-news.dev/@bot",
        "https://ruby.social/@news_kr",
        "https://x.com/rubynewskr"
      ],
      masthead: "#{host}/about"
    )
  end

  def index
    cacheable_page!
    scope = article_scope

    @featured_articles = build_featured_articles(scope)
    @articles = build_recent_articles(scope, excluded_ids: @featured_articles.map(&:id))
    @liked_article_ids = liked_article_ids_for(@articles, @featured_articles)
    @boosted_article_ids = boosted_article_ids_for(@articles, @featured_articles)
    @news_media_organization = self.class.publisher_schema(Hosts.locale_for_host(request.host))
    @recent_comments = recent_comments
    @recent_blog_posts = Post.recent_published_blogs
    @sidebar_tags = sidebar_tags
    render Views::Home::Index.new(
      articles: @articles,
      featured_articles: @featured_articles,
      recent_comments: @recent_comments,
      recent_blog_posts: @recent_blog_posts,
      sidebar_tags: @sidebar_tags,
      liked_article_ids: @liked_article_ids,
      boosted_article_ids: @boosted_article_ids
    )
  end

  # GET /about
  def about
    cacheable_page!
    render Views::Home::About.new
  end

  # GET /privacy-policy
  def privacy_policy
    cacheable_page!
    render Views::Home::PrivacyPolicy.new
  end

  # GET /terms
  def terms
    cacheable_page!
    render Views::Home::Terms.new
  end

  # GET /rss
  def rss
    cacheable_page!(max_age: 1.hour)
    # to_a 가 핵심이다. Relation 을 그대로 캐시하면 레코드가 아니라 쿼리가
    # 직렬화되므로, 캐시 히트마다 SQL 이 다시 나가 캐시가 아무것도 아껴주지 못한다.
    # 게다가 without_toast 가 select(column_names - ...) 로 컬럼 목록을 문자열
    # 배열로 굳혀 두기 때문에, 캐시가 살아 있는 동안 컬럼이 리네임되면 옛 이름으로
    # 질의해 PG::UndefinedColumn 이 난다(federails_actor_id 리네임 때 실제 발생).
    # with_attached_thumbnail 은 뷰의 thumbnail.blob 접근이 캐시 히트마다
    # N+1 을 내지 않도록 blob 까지 함께 적재한다.
    @articles = Rails.cache.fetch(Article::RSS_CACHE_KEY, expires_in: 1.hour) do
      Article.includes(:user, :site).with_attached_thumbnail
             .kept.confirmed.related.without_toast
             .order(created_at: :desc).limit(100).to_a
    end
    response.headers["Content-Type"] = "application/rss+xml; charset=utf-8"
    render "rss", formats: [ :rss ], layout: false
  end

  # GET /llms.txt — 요청 호스트별 llms.txt 동적 서빙.
  # public 캐시(max-age=1day)이므로 쿠키·사용자 로케일이 아니라 request.host 로
  # 본문을 결정해야 캐시 오염(다른 방문자에게 잘못된 언어 제공)을 방지한다.
  def llms
    cacheable_page!(max_age: 1.day)
    body = LLMS_TXT.fetch(Hosts.locale_for_host(request.host))
    render plain: body, content_type: "text/plain"
  end

  # GET /robots.txt — 요청 호스트별 robots.txt 동적 서빙.
  # .dev/.jp 를 독립 사이트로 취급하므로 각 도메인은 자기 로케일 사이트맵만
  # 광고한다(정적 robots.txt 하나가 양 도메인 사이트맵을 함께 노출하던 것을 분리).
  # llms.txt 와 마찬가지로 request.host 기준으로 본문을 결정해 public 캐시 오염을 막는다.
  def robots
    cacheable_page!(max_age: 1.day)
    locale = Hosts.locale_for_host(request.host)
    host = Hosts.for_locale(locale)
    # gsub(리터럴 치환)을 쓴다. format 은 robots.txt 에 URL 인코딩(%20) 등
    # 다른 % 가 유입되면 ArgumentError(malformed format string)로 렌더가 깨진다.
    body = ROBOTS_TXT.gsub("%{sitemap}", "#{host}/sitemaps/#{locale}/sitemap.xml.gz")
    render plain: body, content_type: "text/plain"
  end

  private

  # llms.txt 본문은 정적 텍스트 파일에서 로드한다 (app/views/home/llms/{ko,ja}.txt).
  LLMS_TXT = {
    ko: Rails.root.join("app/views/home/llms/ko.txt").read.freeze,
    ja: Rails.root.join("app/views/home/llms/ja.txt").read.freeze
  }.freeze

  # robots.txt 템플릿(%{sitemap} 자리표시자). 호스트별 Sitemap 만 치환한다.
  ROBOTS_TXT = Rails.root.join("app/views/home/robots.txt").read.freeze

  def article_scope
    Article.includes(:user, :site).with_attached_thumbnail.kept.confirmed.related
  end

  def build_featured_articles(scope)
    featured_scope = scope.without_toast.where(created_at: 48.hours.ago...)
    featured_articles = primary_featured_articles(featured_scope)

    if featured_articles.size < 3
      featured_articles.concat(fallback_featured_articles(featured_scope, featured_articles))
    end

    featured_articles.sort_by { [ -it.likers_count, -it.boosters_count, -it.posts_count, -it.published_at.to_i, -it.created_at.to_i ] }
  end

  def primary_featured_articles(featured_scope)
    featured_scope
      .where("likers_count > ? OR posts_count > ? OR boosters_count > ?", 0, 0, 0)
      .order(likers_count: :desc, posts_count: :desc, boosters_count: :desc, created_at: :desc)
      .limit(3)
      .to_a
  end

  def fallback_featured_articles(featured_scope, featured_articles)
    featured_scope
      .where.not(id: featured_articles.map(&:id))
      .order(published_at: :desc, created_at: :desc)
      .limit(3 - featured_articles.size)
      .to_a
  end

  def build_recent_articles(scope, excluded_ids:)
    remaining_scope = scope.where.not(id: excluded_ids)
    articles = if remaining_scope.where(created_at: 24.hours.ago...).count < 9
      remaining_scope.without_toast.order(created_at: :desc).limit(9)
    else
      remaining_scope.without_toast.where(created_at: 24.hours.ago...).order(created_at: :desc)
    end

    articles.sort_by { -it.published_at.to_i }
  end

  def liked_article_ids_for(articles, featured_articles)
    Like.liked_ids_for(
      liker: current_user,
      likeable_type: "Article",
      likeable_ids: (articles + featured_articles).map(&:id)
    )
  end

  def boosted_article_ids_for(articles, featured_articles)
    Boost.boosted_ids_for(
      booster: current_user,
      boostable_type: "Article",
      boostable_ids: (articles + featured_articles).map(&:id)
    )
  end

  def recent_comments
    Post.comments.kept
      .joins(:article)
      .preload(:article, :fedipub_actor, user: { avatar_attachment: :blob })
      .where(article: { deleted_at: nil })
      .order(created_at: :desc)
      .limit(10)
  end

  def sidebar_tags
    Tag.confirmed.order(taggings_count: :desc, name: :asc).limit(20)
  end
end
