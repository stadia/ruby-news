# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

module SitemapBuilder
  extend FunctionLogger

  # 단일 소스: app/functions/hosts.rb (Hosts::FOR_LOCALE)
  HREFLANG_HOSTS = Hosts::FOR_LOCALE

  # published_at은 원문에서 파싱되므로 비현실적 값(예: 1935년, 미래 날짜)이
  # 들어올 수 있고, 그대로 lastmod에 쓰면 Google Search Console이 "잘못된
  # 날짜"로 사이트맵을 거부한다. Rails 등장(2004) 이전 floor로 사용한다.
  MIN_LASTMOD = Time.zone.local(2004, 1, 1)

  # 링크를 5,000개마다 디스크로 flush하고 버퍼를 비운다. 기본값(50,000)이면
  # 전체 링크(<50k)를 한 버퍼에 통째로 물고 있다가 flush해 순간 메모리 peak가
  # 컸다. 이 빌드는 장수명 solid_queue 워커 안에서 돌므로 그 스파이크가 워커
  # 컨테이너 OOM을 유발했다. 값이 낮을수록 peak↓·사이트맵 파일수↑(둘 다 무해).
  MAX_SITEMAP_LINKS = 5_000

  # 사이트맵에 등재할 문서 1건의 경량 표현. DB를 한 번만 순회해 이 값들을 모아
  # ko/ja 빌드가 공유한다(AR 객체를 로케일마다 다시 읽지 않는다).
  #   available: 번역이 존재하는 로케일 키 배열(예: ["ko", "ja"] 또는 ["ko"])
  # 멤버 타입: sorbet/rbi/shims/data_definitions.rbi
  Entry = Data.define(:path, :lastmod, :available)

  # 사이트맵 수집에 쓰는 컬럼만 읽는다. 매시 전체 기사를 순회하므로 body·summary_body·
  # embedding 같은 TOAST 컬럼까지 읽으면 불필요한 DB I/O와 역직렬화 비용이 커진다.
  # id는 find_in_batches의 커서, 나머지는 경로(slug)·lastmod_for·available_in?(ja)가 쓴다.
  ARTICLE_COLUMNS = %i[id slug published_at updated_at summary_key_ja].freeze

  # 본문·제목·연관 객체 전체를 읽지 않고 공개 경로와 날짜만 수집한다.
  BLOG_COLUMNS = %i[id slug published_at updated_at].freeze

  class << self
    # Sorbet은 `include`에 상수 리터럴만 허용해 런타임에 만들어지는 라우트 헬퍼
    # 모듈을 직접 넘길 수 없다(srb.help/4002). `send`로 우회한다.
    send(:include, Rails.application.routes.url_helpers)

    # lastmod는 실제 문서 변경 시점을 나타내야 하므로 published_at만 쓰면
    # 발행 이후 제목/요약/번역 수정이 검색엔진에 전달되지 않는다.
    # 별도 content_updated_at이 없으므로 안전한 published_at/updated_at 중 최신값을 사용한다.
    #: (Article | Post) -> String?
    def lastmod_for(article)
      [ article.published_at, article.updated_at ]
        .compact
        .select { |candidate| realistic_lastmod?(candidate) }
        .max
        &.iso8601
    end

    #: (ActiveSupport::TimeWithZone) -> bool
    def realistic_lastmod?(candidate)
      candidate >= MIN_LASTMOD && candidate <= Time.current
    end

    # 도메인별로 자기 완결적인 사이트맵을 생성한다. 로케일마다 별도 LinkSet을
    # 만들어 인덱스·자식 사이트맵·<loc>가 모두 자기 호스트(ko=.dev, ja=.jp)에
    # 속하도록 한다. 이전에는 단일 LinkSet(default_host 하드코딩)이 양 도메인에
    # 공유돼, .jp 인덱스가 .dev 자식을 가리키는 크로스도메인 참조가 생겼고
    # GSC가 사이트맵 귀속을 하지 못했다(참조 페이지가 반대 도메인으로 잡힘).
    # Sitemaps.org 프로토콜의 "한 사이트맵의 URL은 단일 호스트" 원칙도 준수한다.
    #: () -> void
    def build
      # 문서별로 한 번씩 수집한 경량 배열을 ko/ja 빌드가 공유한다.
      entries = collect_article_entries.concat(collect_blog_entries)
      HREFLANG_HOSTS.each { |locale, host| build_locale(locale, host, entries) }
    end

    # 사이트맵에 등재할 기사를 DB에서 한 번만 순회해 경량 Entry 배열로 수집한다.
    # AR 객체가 아니라 값(경로·lastmod·가용 로케일)만 담으므로 메모리 부담이 작다.
    #: () -> Array[Entry]
    def collect_article_entries
      entries = []
      Article.kept
             .confirmed
             .select(ARTICLE_COLUMNS)
             .find_in_batches(batch_size: 500) do |batch|
        batch.each do |article|
          # 번역이 존재하는 로케일만 등재 대상. 일본어 번역이 없는 기사는
          # .jp(ja) 사이트맵의 <loc>·alternate 에서 빠져 한국어 폴백을 일본어로
          # 색인시키지 않는다. 번역되면 다음 빌드에서 자동 포함.
          available = HREFLANG_HOSTS.keys.select { |loc| article.available_in?(loc) }
          next if available.empty?

          path = article_path(article.slug)
          entries << Entry.new(
            path: path,
            lastmod: lastmod_for(article),
            available: available
          )
        end
      end
      entries
    end

    # 작성자가 없는 원격 글은 /@:username/blog/:slug로 공개할 수 없어 제외한다.
    # users와의 일대일 조인 및 posts.slug의 UNIQUE 제약으로 URL 중복도 발생하지 않는다.
    #: () -> Array[Entry]
    def collect_blog_entries
      entries = []
      Post.published_blog.kept
          .joins(:user)
          .select(BLOG_COLUMNS)
          .select(User.arel_table[:username].as("sitemap_username"))
          .find_in_batches(batch_size: 500) do |batch|
        batch.each do |post|
          username = post.read_attribute("sitemap_username")
          slug = post.slug
          next unless valid_blog_segment?(username) && valid_blog_segment?(slug)
          next if [ ".", ".." ].include?(slug)

          entries << Entry.new(
            path: user_profile_blog_post_path(username:, slug:),
            lastmod: lastmod_for(post),
            available: [ "ko" ]
          )
        end
      end
      entries
    end

    # URL 헬퍼가 유니코드 등을 이스케이프하지만 경로 구분자는 별도로 제외한다.
    #: (String?) -> bool
    def valid_blog_segment?(value)
      return false if value.nil? || value.blank?

      !value.include?("/")
    end

    # 단일 로케일/호스트에 대한 자기 완결 사이트맵(인덱스 + 샤드)을 생성한다.
    # 출력: public/sitemaps/<locale>/sitemap.xml.gz (+ sitemap1..N.xml.gz)
    #: (String, String, Array[Entry]) -> void
    def build_locale(locale, host, entries)
      link_set = SitemapGenerator::LinkSet.new(
        default_host: host,
        sitemaps_path: "sitemaps/#{locale}/",
        include_root: false,
        compress: true,
        max_sitemap_links: MAX_SITEMAP_LINKS
      )

      # create 블록은 Interpreter 컨텍스트에서 instance_eval 되므로 self가 DSL
      # (add 응답)이 된다. 실제 링크 등재 로직은 populate 로 분리해 테스트를
      # 용이하게 하고, locale/host/entries 는 클로저로 캡처된다.
      link_set.create { SitemapBuilder.populate(self, locale, host, entries) }
    end

    # 주어진 로케일/호스트의 URL을 DSL(add 응답 객체)에 등재한다. 정적 페이지와,
    # 미리 수집된 문서 Entry 중 해당 로케일을 지원하는 것만 자기 호스트 <loc>로
    # 넣는다. 두 도메인(.dev/.jp)은 완전히 독립적인 사이트로 취급하므로 로케일 간
    # hreflang 상호 참조(alternates)는 붙이지 않는다.
    #: (untyped, String, String, Array[Entry]) -> void
    def populate(dsl, locale, host, entries)
      # 목록 페이지 lastmod: 맨 날짜(Date)는 타임존이 없어 파서가 UTC 자정으로
      # 해석 → KST 오늘이 UTC 기준 미래로 보인다. 오프셋이 붙는 Time을 사용.
      index_lastmod = Time.current.iso8601
      [ root_path, articles_path, others_path ].each do |path|
        dsl.add path, host: host, lastmod: index_lastmod
      end

      entries.each do |entry|
        next unless entry.available.include?(locale)

        dsl.add entry.path, host: host, lastmod: entry.lastmod
      end
    end
  end
end
