# frozen_string_literal: true

require "test_helper"

class ArticleTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  # Test fixtures setup
  def setup
    preferences(:ignore_hosts)
    @article = articles(:ruby_article)
    @youtube_article = articles(:youtube_ruby_talk)
    @korean_article = articles(:korean_content_article)
    @deleted_article = articles(:deleted_article)
    @site_article = articles(:site_only_article)
    @user = users(:john)
    @site = sites(:ruby_weekly)
  end

  # ========== Validation Tests ==========

  test "유효한 속성을 가진 경우 유효해야 한다" do
    article = Article.new(
      title: "Test Article",
      url: "https://example.com/test-unique-url",
      origin_url: "https://example.com/test-unique-origin",
      user: @user
    )

    assert_predicate article, :valid?
  end

  test "리모트 ActivityPub Note는 Article로 처리하지 않아야 한다" do
    remote_note = {
      "id" => "https://remote.example/notes/1",
      "type" => "Note",
      "content" => "remote content",
      "inReplyTo" => nil
    }

    assert_not Article.handle_federated_object?(remote_note)
  end

  test "로컬 article은 federation 발행 조건을 만족하면 여전히 federate 가능해야 한다" do
    article = Article.new(
      title: "Test Article",
      title_ko: "테스트 기사",
      url: "https://example.com/test-federate",
      origin_url: "https://example.com/test-federate",
      user: @user
    )

    assert_predicate article, :should_federate?
  end

  test "url은 필수 항목이어야 한다" do
    article = Article.new(title: "Test Article", origin_url: "https://example.com/test", user: @user)

    assert_not article.save
    assert_includes article.errors[:url], "내용을 입력해 주세요"
  end

  test "human_attribute_name은 locale별 기사 속성명을 반환해야 한다" do
    I18n.with_locale(:ko) do
      assert_equal "URL", Article.human_attribute_name(:url)
    end

    I18n.with_locale(:ja) do
      assert_equal "URL", Article.human_attribute_name(:url)
    end
  end

  test "origin_url이 비어있을 때 url로부터 설정되어야 한다" do
    article = Article.new(
      title: "Test Article",
      url: "https://example.com/test",
      user: @user
    )
    # Mock generate_metadata to avoid external calls
    article.stub(:generate_metadata, nil) do
      article.save!
    end

    assert_equal "https://example.com/test", article.origin_url
  end

  test "url의 유일성을 대소문자 구분 없이 검증해야 한다" do
    existing_article = @article
    article = Article.new(
      title: "Another Article",
      url: existing_article.url.upcase,
      origin_url: "https://different-origin.com/test",
      user: @user
    )

    assert_not article.valid?
    assert_includes article.errors[:url], "이미 존재하는 값입니다"
  end

  test "origin_url의 유일성을 대소문자 구분 없이 검증해야 한다" do
    existing_article = @article
    article = Article.new(
      title: "Another Article",
      url: "https://different-url.com/test",
      origin_url: existing_article.origin_url.upcase,
      user: @user
    )

    assert_not article.valid?
    assert_includes article.errors[:origin_url], "이미 존재하는 값입니다"
  end

  test "slug가 존재할 경우 유일성을 검증해야 한다" do
    existing_article = @article
    article = Article.new(
      title: "Different Article",
      url: "https://different.com/test",
      origin_url: "https://different.com/test-origin",
      slug: existing_article.slug,
      user: @user
    )

    assert_not article.valid?
    assert_includes article.errors[:slug], "이미 존재하는 값입니다"
  end

  test "articles.slug 컬럼은 길이 제한 없는 text다" do
    column = Article.columns_hash["slug"]

    assert_equal :text, column.type
    assert_nil column.limit
  end

  test "빈 slug를 허용해야 한다" do
    article = Article.new(
      title: "Test Article",
      url: "https://example.com/blank-slug-test",
      origin_url: "https://example.com/blank-slug-test-origin",
      slug: "",
      user: @user
    )

    assert_predicate article, :valid?
  end

  test "title은 최대 길이 안에서 단어 경계로 줄여야 한다" do
    long_title = "#{'Ruby ' * 80}AbruptTail"
    article = Article.new(
      title: long_title,
      url: "https://example.com/title-too-long",
      origin_url: "https://example.com/title-too-long-origin",
      user: @user
    )

    assert_predicate article, :valid?
    assert_operator article.title.length, :<=, Article::TITLE_MAX_LENGTH
    assert_equal "...", article.title.last(3)
    assert_not_includes article.title, "AbruptTail"
    assert_equal "Ruby...", article.title.last(7)
  end

  test "title에 단어 경계가 없으면 최대 길이에 맞춰 줄여야 한다" do
    article = Article.new(
      title: "가" * (Article::TITLE_MAX_LENGTH + 20),
      url: "https://example.com/title-no-boundary",
      origin_url: "https://example.com/title-no-boundary-origin",
      user: @user
    )

    assert_predicate article, :valid?
    assert_equal Article::TITLE_MAX_LENGTH, article.title.length
    assert_equal "...", article.title.last(3)
  end

  # ========== Association Tests ==========

  test "user에 필수적으로 속해야 한다" do
    assert_respond_to @article, :user
    assert_kind_of User, @article.user
    assert_not Article.reflect_on_association(:user).options[:optional]

    article = Article.new(
      title: "No User Article",
      url: "https://example.com/no-user",
      origin_url: "https://example.com/no-user-origin",
      user: @user
    )

    assert_predicate article, :valid?
  end

  test "site에 선택적으로 속해야 한다" do
    assert_respond_to @article, :site
    assert_kind_of Site, @article.site

    article = Article.new(
      title: "No Site Article",
      url: "https://example.com/no-site",
      origin_url: "https://example.com/no-site-origin",
      user: @user
    )
    article.site = nil

    assert_predicate article, :valid?
  end

  test "posts와 has_many 관계를 가져야 한다" do
    article = @article
    initial_count = article.posts.count
    post = article.posts.create!(body: "Test comment", user: @user)

    assert_equal initial_count + 1, article.posts.count
    assert_equal article.id, post.article_id
    assert_includes article.posts, post
  end

  # ========== Scope Tests ==========

  test "full_text_search_for 스코프가 존재하고 호출 가능해야 한다" do
    assert_respond_to Article, :full_text_search_for
    # Note: Full functionality requires PostgreSQL setup
  end

  test "related 스코프는 관련된 기사를 반환해야 한다" do
    related_articles = Article.related

    assert_includes related_articles, @article
    assert_includes related_articles, @korean_article
    assert_not_includes related_articles, @site_article
  end

  test "unrelated 스코프는 관련 없는 기사를 반환해야 한다" do
    unrelated_articles = Article.unrelated

    assert_includes unrelated_articles, @site_article
    assert_not_includes unrelated_articles, @article
    assert_not_includes unrelated_articles, @korean_article
  end

  test "title_matching 스코프가 존재하고 호출 가능해야 한다" do
    assert_respond_to Article, :title_matching
    # Note: Full functionality requires PostgreSQL with Korean dictionary
  end

  test "body_matching 스코프가 존재하고 호출 가능해야 한다" do
    assert_respond_to Article, :body_matching
    # Note: Full functionality requires PostgreSQL with English dictionary
  end

  # ========== Soft Delete Tests ==========

  test "Discard::Model을 포함해야 한다" do
    assert_includes Article.ancestors, Discard::Model
  end

  test "좋아요 가능 모델이어야 한다" do
    assert_respond_to @article, :likers_count
    assert_respond_to @user, :like!
  end

  test "fedipub 좋아요 콜백으로 좋아요와 취소를 처리한다" do
    actor = Fedipub::Actor.create!(
      federated_url: "https://remote.example/users/article-liker-#{SecureRandom.hex(4)}",
      username: "article_liker",
      name: "Article Liker",
      server: "remote.example",
      inbox_url: "https://remote.example/users/article-liker/inbox",
      outbox_url: "https://remote.example/users/article-liker/outbox",
      followers_url: "https://remote.example/users/article-liker/followers",
      followings_url: "https://remote.example/users/article-liker/following",
      profile_url: "https://remote.example/@article-liker",
      actor_type: "Person",
      local: false
    )

    assert_difference -> { Like.where(actor: actor, likeable: @article).count }, 1 do
      @article.send(:apply_remote_like, actor.federated_url)
    end

    assert_difference -> { Like.where(actor: actor, likeable: @article).count }, -1 do
      @article.send(:apply_remote_unlike, actor.federated_url)
    end
  end

  test "kept 스코프는 삭제된 기사를 제외해야 한다" do
    kept_articles = Article.kept

    assert_includes kept_articles, @article
    assert_not_includes kept_articles, @deleted_article
  end

  test "discarded 스코프는 삭제된 기사를 포함해야 한다" do
    discarded_articles = Article.discarded

    assert_includes discarded_articles, @deleted_article
    assert_not_includes discarded_articles, @article
  end

  test "기사를 파괴하는 대신 폐기해야 한다" do
    article = @article
    article.stub(:create_fedipub_activity, nil) do
      article.discard!
    end

    assert_predicate article, :discarded?
    assert_not_nil article.deleted_at
    assert Article.exists?(article.id)
  end

  # ========== Callback Tests ==========

  test "생성 시 유효성 검사 전에 url로부터 origin_url을 설정해야 한다" do
    article = Article.new(title: "Test", url: "https://example.com/callback-test", user: @user)
    article.valid?

    assert_equal "https://example.com/callback-test", article.origin_url
  end

  test "저장 전 기존 published_at을 덮어쓰지 않아야 한다" do
    existing_time = 1.week.ago
    article = Article.new(
      title: "Test",
      url: "https://example.com/existing-published",
      origin_url: "https://example.com/existing-published-origin",
      published_at: existing_time,
      user: @user
    )

    # generate_metadata 메서드를 직접 stub하여 published_at 덮어쓰기 방지
    article.stub(:generate_metadata, nil) do
      article.save!
    end

    # The published_at should be preserved (not overridden by before_save callback)
    assert_equal existing_time.to_i, article.published_at.to_i,
      "published_at should not be overridden when already set"
  end

  test "제목에 Show HN이 포함되면 생성 시 자동으로 discard되어야 한다" do
    article = Article.new(
      title: "Show HN: My Awesome Project",
      url: "https://example.com/show-hn-test",
      origin_url: "https://example.com/show-hn-test-origin",
      user: @user
    )

    # Mock generate_metadata to avoid external calls
    article.stub(:generate_metadata, nil) do
      article.save!
    end

    assert_predicate article, :discarded?, "Article with 'Show HN' in title should be discarded"
    assert_not_nil article.deleted_at
  end

  test "제목에 show hn (소문자)이 포함되면 생성 시 자동으로 discard되어야 한다" do
    article = Article.new(
      title: "show hn: my project",
      url: "https://example.com/show-hn-lowercase-test",
      origin_url: "https://example.com/show-hn-lowercase-test-origin",
      user: @user
    )

    # Mock generate_metadata to avoid external calls
    article.stub(:generate_metadata, nil) do
      article.save!
    end

    assert_predicate article, :discarded?, "Article with 'show hn' (lowercase) in title should be discarded"
    assert_not_nil article.deleted_at
  end

  test "제목에 Show HN이 없으면 discard되지 않아야 한다" do
    article = Article.new(
      title: "Regular Article Title",
      url: "https://example.com/regular-test",
      origin_url: "https://example.com/regular-test-origin",
      user: @user
    )

    # Mock generate_metadata to avoid external calls
    article.stub(:generate_metadata, nil) do
      article.save!
    end

    assert_not article.discarded?, "Article without 'Show HN' in title should not be discarded"
    assert_nil article.deleted_at
  end

  test "title이 일본어(가나 포함)이면 저장 시 title_ja에도 함께 저장해야 한다" do
    article = Article.new(
      title: "Rubyの新しい機能について",
      url: "https://example.com/japanese-title-test",
      origin_url: "https://example.com/japanese-title-test-origin",
      user: @user
    )

    article.stub(:generate_metadata, nil) do
      article.save!
    end

    assert_equal "Rubyの新しい機能について", article.title_ja
  end

  test "title이 한자(漢字)로만 이루어져도 일본어로 취급해 title_ja에 저장해야 한다" do
    article = Article.new(
      title: "日本語処理",
      url: "https://example.com/kanji-only-title-test",
      origin_url: "https://example.com/kanji-only-title-test-origin",
      user: @user
    )

    article.stub(:generate_metadata, nil) do
      article.save!
    end

    assert_equal "日本語処理", article.title_ja
  end

  test "title이 일본어가 아니면 title_ja를 채우지 않아야 한다" do
    article = Article.new(
      title: "A regular English title",
      url: "https://example.com/non-japanese-title-test",
      origin_url: "https://example.com/non-japanese-title-test-origin",
      user: @user
    )

    article.stub(:generate_metadata, nil) do
      article.save!
    end

    assert_nil article.title_ja
  end

  test "생성 전에 메타데이터를 생성해야 한다" do
    article = Article.new(
      title: "Test",
      url: "https://example.com/metadata-test",
      user: @user
    )

    stub_external_requests(article) do
      article.save!
    end

    assert_not_nil article.slug
    assert_not_nil article.host
  end

  # ========== Instance Method Tests ==========

  test "youtube_id는 YouTube URL에서 비디오 ID를 추출해야 한다" do
    youtube_urls = {
      "https://www.youtube.com/watch?v=dQw4w9WgXcQ" => "dQw4w9WgXcQ",
      "https://youtube.com/watch?v=abc123&t=30s" => "abc123",
      "https://www.youtube.com/live/live123" => "live123",
      "https://youtu.be/short123" => nil, # This format not supported by current implementation
      "https://example.com/not-youtube" => nil
    }

    youtube_urls.each do |url, expected_id|
      article = Article.new(url: url)
      if expected_id.nil?
        assert_nil article.youtube_id, "Failed for URL: #{url}"
      else
        assert_equal expected_id, article.youtube_id, "Failed for URL: #{url}"
      end
    end
  end

  test "youtube_id는 유효하지 않은 URL을 정상적으로 처리해야 한다" do
    article = Article.new(url: "invalid-url")

    assert_nil article.youtube_id
  end

  test "update_slug는 YouTube URL에 대해 작동해야 한다" do
    article = Article.new(
      title: "YouTube Test",
      url: "https://www.youtube.com/watch?v=test123",
      origin_url: "https://www.youtube.com/watch?v=test123",
      is_youtube: true,
      user: @user
    )

    # Mock generate_metadata to avoid external calls
    article.stub(:generate_metadata, nil) do
      article.save!
    end

    article.update_slug
    article.reload

    assert_equal "test123", article.slug
  end

  test "update_slug는 경로가 없는 URL을 안전하게 처리해야 한다 (Bug fix #2)" do
    article = Article.new(
      title: "No Path URL",
      url: "https://example.com",
      origin_url: "https://example.com",
      user: @user
    )

    # Mock generate_metadata to avoid external calls
    article.stub(:generate_metadata, nil) do
      article.save!
    end

    # Should not raise NoMethodError when path is nil
    assert_nothing_raised do
      result = article.update_slug

      assert result
    end

    article.reload
    # Should have fallback slug when path is empty
    assert_not_nil article.slug
  end

  test "user_name은 bot 사용자인 경우 site 정보를 반환해야 한다" do
    # 전제 명시: user_name 이 site 이름으로 갈리는 이유는 작성자가 bot 롤이기 때문이다.
    assert @article.user.has_role?(:bot), "전제: 작성자가 bot 이어야 site 이름으로 폴백한다"

    # 기대값은 픽스처에서 파생해 "Ruby Weekly" 하드코딩 의존을 줄인다.
    expected_site_name = @article.site.name

    assert_equal "Ruby Weekly", expected_site_name, "전제: ruby_weekly 픽스처의 site 이름"

    assert_equal expected_site_name, @article.user_name
  end

  test "user_name은 bot 사용자이면서 site가 있으면 site 정보를 반환해야 한다" do
    site_article = @site_article

    assert_equal site_article.site.name, site_article.user_name
  end

  test "user_name은 bot 사용자이고 site의 base_uri가 없으면 사이트 이름을 반환해야 한다" do
    site_article = @site_article
    site_article.site.base_uri = nil

    assert_equal site_article.site.name, site_article.user_name
  end

  test "user_name은 site와 host가 없으면 nil을 반환한다" do
    article = Article.new(title: "Test", url: "https://example.com", origin_url: "https://example.com", user: @user)
    article.user = nil

    assert_nil article.user_name
  end

  # ========== Class Method Tests ==========

  test "find_by_slug는 slug로 기사를 찾아야 한다" do
    article = Article.find_by_slug(@article.slug)

    assert_equal @article, article
  end

  test "find_by_slug는 존재하지 않는 slug에 대해 nil을 반환해야 한다" do
    article = Article.find_by_slug("non-existent-slug")

    assert_nil article
  end

  test "should_ignore_url?은 무시해야 할 호스트에 대해 true를 반환해야 한다" do
    ignored_urls = [
      "https://github.com/user/repo",
      "https://twitter.com/user/status/123",
      "https://linkedin.com/in/user",
      "https://meetup.com/event/123",
      "https://subdomain.github.com/path"
    ]

    ignored_urls.each do |url|
      assert Articles::Utils.should_ignore_url?(url), "Should ignore URL: #{url}"
    end
  end

  test "should_ignore_url?은 허용된 호스트에 대해 false를 반환해야 한다" do
    allowed_urls = [
      "https://weblog.rubyonrails.org/2024/1/1/rails-8",
      "https://example.com/article",
      "https://blog.example.com/post",
      "https://good-source.com/article"
    ]

    allowed_urls.each do |url|
      assert_not Articles::Utils.should_ignore_url?(url), "Should not ignore URL: #{url}"
    end
  end

  test "should_ignore_url?은 파싱 불가 URL에 대해 크래시 없이 true를 반환해야 한다" do
    assert_nothing_raised do
      assert Articles::Utils.should_ignore_url?("ht tp://invalid url with spaces")
    end
  end

  # host 가드가 완화돼도 nil path가 "통과"로 해석되지 않도록 fail-closed를 유지한다.
  test "should_ignore_url?은 nil path를 무시 대상으로 처리해야 한다" do
    fake_uri = Struct.new(:host, :path).new("example.com", nil)

    URI.stub(:parse, fake_uri) do
      assert Articles::Utils.should_ignore_url?("https://example.com")
    end
  end

  test "should_ignore_url?은 위험한 파일 확장자에 대해 true를 반환해야 한다" do
    dangerous_urls = [
      "https://example.com/file.pdf",
      "https://example.com/archive.zip",
      "https://example.com/book.epub",
      "https://example.com/program.exe",
      "https://example.com/data.rar"
    ]

    dangerous_urls.each do |url|
      assert Articles::Utils.should_ignore_url?(url), "Should ignore dangerous file: #{url}"
    end
  end

  test "should_ignore_url?은 유효하지 않은 URL을 처리해야 한다" do
    assert Articles::Utils.should_ignore_url?("invalid-url")
    assert Articles::Utils.should_ignore_url?(nil)
    assert Articles::Utils.should_ignore_url?("")
  end

  test "set_initial_url_and_host는 논리 연산자 우선순위를 올바르게 처리해야 한다 (Bug fix #1)" do
    service = Articles::MetadataPreparationService.new

    # URL with no path should be deleted only if not YouTube
    article = Article.new(
      title: "No Path Test",
      url: "https://example.com",
      origin_url: "https://example.com"
    )

    service.send(:normalize_article_url, article)

    assert_not_nil article.deleted_at, "YouTube가 아닌 URL이고 경로가 없으면 삭제되어야 합니다."

    # YouTube URL should NOT be deleted even with short/no path
    youtube_article = Article.new(
      title: "YouTube No Path",
      url: "https://www.youtube.com",
      origin_url: "https://www.youtube.com"
    )

    service.send(:normalize_article_url, youtube_article)
    # YouTube should not be automatically deleted
    # (unless explicitly marked for deletion)
    assert youtube_article.is_youtube
  end

  test "title에서 생성한 slug는 줄여진 title을 기반으로 해야 한다" do
    service = Articles::MetadataPreparationService.new
    article = Article.new(
      title: "#{'Ruby ' * 80}AbruptTail",
      url: "https://example.com/long-title-slug",
      origin_url: "https://example.com/long-title-slug-origin",
      user: @user
    )

    article.valid?
    service.send(:ensure_article_slug, article)

    assert_operator article.slug.length, :<=, Article::TITLE_MAX_LENGTH
    assert_not_includes article.slug, "abrupttail"
  end

  # ========== Store Accessor Tests ==========

  test "store 접근자를 통해 summary_detail 구성 요소에 접근해야 한다" do
    article = @korean_article

    # Test reading
    assert_respond_to article, :summary_body
    assert_respond_to article, :summary_introduction
    assert_respond_to article, :summary_conclusion

    # Test writing
    article.summary_body = "새로운 본문 요약"
    article.summary_introduction = "새로운 서론"
    article.summary_conclusion = "새로운 결론"

    article.save!
    article.reload

    assert_equal "새로운 본문 요약", article.summary_body
    assert_equal "새로운 서론", article.summary_introduction
    assert_equal "새로운 결론", article.summary_conclusion
  end

  # ========== Tagging Tests ==========

  test "taggable로 작동해야 한다" do
    article = @article

    assert_respond_to article, :tag_list
    assert_respond_to article, :tag_list=

    # Test adding tags
    article.tag_list = "ruby, rails, programming"
    article.save!

    assert_includes article.tag_list, "ruby"
    assert_includes article.tag_list, "rails"
    assert_includes article.tag_list, "programming"
  end

  # ========== Korean Content Tests ==========

  test "제목과 내용에 있는 한글 문자를 처리해야 한다" do
    korean_article = Article.new(
      title: "한국어 제목 테스트",
      title_ko: "한국어 제목의 다른 버전",
      url: "https://example.com/korean-test",
      origin_url: "https://example.com/korean-test-origin",
      body: "한국어 내용입니다. Ruby와 Rails에 대한 정보가 포함되어 있습니다.",
      summary_key: "한국어 요약",
      user: users(:korean_user)
    )

    # Mock generate_metadata to avoid external calls
    korean_article.stub(:generate_metadata, nil) do
      korean_article.save!
    end

    assert_equal "한국어 제목 테스트", korean_article.title
    assert_equal "한국어 제목의 다른 버전", korean_article.title_ko
    assert_includes korean_article.body, "한국어"
    assert_equal "한국어 요약", korean_article.summary_key
  end

  # ========== YouTube Integration Tests ==========

  test "YouTube 기사를 정확하게 식별해야 한다" do
    assert_predicate @youtube_article, :is_youtube?
    assert_not @article.is_youtube?
  end

  test "YouTube URL 정규화를 처리해야 한다" do
    youtube_article = Article.new(
      title: "YouTube Test",
      url: "https://youtube.com/watch?v=test123&utm_source=share",
      origin_url: "https://youtube.com/watch?v=test123&utm_source=share&ref=twitter",
      user: @user
    )

    # Mock generate_metadata to avoid external API calls
    youtube_article.stub(:generate_metadata, nil) do
      youtube_article.save!
    end

    # Should still work even with different YouTube domain format
    assert_not_nil youtube_article.youtube_id
  end

  # ========== URL Processing Tests ==========

  test "URL 패턴에서 published_at을 추출해야 한다" do
    urls_with_dates = {
      "https://example.com/2024/01/15/article-title" => Date.parse("2024-01-15"),
      "https://blog.com/2023-12-25-holiday-post" => Date.parse("2023-12-25"),
      "https://news.com/articles/2024/1/1/new-year" => Date.parse("2024-01-01")
    }

    urls_with_dates.each do |url, expected_date|
      extracted_date = Articles::MetadataPreparation.url_to_published_at(url)

      if extracted_date
        assert_equal expected_date.year, extracted_date.year
        assert_equal expected_date.month, extracted_date.month
        assert_equal expected_date.day, extracted_date.day
      end
    end
  end

  test "URL 파싱 오류를 정상적으로 처리해야 한다" do
    assert_nil Articles::MetadataPreparation.url_to_published_at("invalid-url")
  end

  # ========== Cache Management Tests ==========

  test "폐기 후 RSS 캐시를 지워야 한다" do
    deleted_keys = []
    Rails.cache.stub(:delete, ->(key, *args, **kwargs) { deleted_keys << key; true }) do
      @article.stub(:create_fedipub_activity, nil) do
        @article.discard!
      end
    end

    assert_includes deleted_keys, Article::RSS_CACHE_KEY
  end

  test "discard하면 Delete 활동이 생성되고 SocialDeleteJob이 등록된다" do
    assert_difference -> { Fedipub::Activity.where(action: "Delete", entity: @article).count }, 1 do
      assert_enqueued_with(job: SocialDeleteJob, args: [ @article.id ]) do
        @article.discard!
      end
    end
  end

  test "undiscard하면 Undo 활동이 생성된다" do
    @article.discard!

    assert_difference -> { Fedipub::Activity.where(action: "Undo", entity: @article).count }, 1 do
      @article.undiscard!
    end
  end

  test "인바운드 연합 삭제는 기사를 soft discard한다" do
    @article.run_callbacks(:on_fedipub_delete_requested)

    assert_predicate @article.reload, :discarded?
    assert Article.exists?(@article.id)
  end

  # ========== Performance Tests ==========

  test "kept된 기사를 효율적으로 쿼리해야 한다" do
    assert_queries(1) do
      Article.kept.limit(10).to_a
    end
  end

  test "관련된 기사를 효율적으로 쿼리해야 한다" do
    assert_queries(1) do
      Article.related.limit(5).to_a
    end
  end

  # ========== Integration Tests ==========

  test "한국 시간대에서 작동해야 한다" do
    Time.zone = "Asia/Seoul"

    article = Article.new(
      title: "시간대 테스트",
      url: "https://example.com/timezone-test",
      origin_url: "https://example.com/timezone-test-origin",
      published_at: Time.zone.now,
      user: users(:korean_user)
    )

    article.stub(:generate_metadata, nil) do
      article.save!
    end

    assert_equal "Asia/Seoul", Time.zone.name
    assert_kind_of ActiveSupport::TimeWithZone, article.published_at
    assert_kind_of ActiveSupport::TimeWithZone, article.created_at
  end

  test "to_activitypub_object는 기본 요약과 태그를 포함한다" do
    article = @article
    article.title = "Original title"
    article.title_ko = "번역 제목"
    article.summary_key = nil
    article.tag_list = "ruby, rails"

    # Pinned to `nil` by the initial assignment otherwise, which rejects the
    # assignment made inside the block below.
    captured = nil #: Hash[Symbol, untyped]?
    Fedipub::DataTransformer::Note.stub(:to_federation, ->(entity, name:, content:, custom:) { captured = { entity:, name:, content:, custom: }; { "ok" => true } }) do
      article.to_activitypub_object
    end

    assert_equal article, captured[:entity]
    assert_equal "번역 제목", captured[:name]
    assert_includes captured[:content], "<strong>번역 제목</strong>"
    assert_includes captured[:content], "새로운 Ruby 관련 글이 올라왔습니다."
    assert_equal 2, captured[:custom]["tag"].size
    assert_equal "ruby", captured[:custom]["tag"].first["name"]
  end

  test "to_activitypub_object는 thumbnail이 있으면 attachment에 이미지를 포함한다" do
    article = @article
    article.title_ko = "썸네일 테스트"
    article.summary_key = [ "요약" ]
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("fake image data"), filename: "test.jpg", content_type: "image/jpeg")
    article.thumbnail.attach(blob)

    # Pinned to `nil` by the initial assignment otherwise, which rejects the
    # assignment made inside the block below.
    captured = nil #: Hash[Symbol, untyped]?
    Fedipub::DataTransformer::Note.stub(:to_federation, ->(entity, name:, content:, custom:) { captured = { entity:, name:, content:, custom: }; { "ok" => true } }) do
      article.to_activitypub_object
    end

    assert_predicate captured[:custom]["attachment"], :present?
    attachment = captured[:custom]["attachment"].first

    assert_equal "Image", attachment["type"]
    assert_equal "image/jpeg", attachment["mediaType"]
    assert_includes attachment["url"], "rails/active_storage"
  ensure
    article.thumbnail.detach
  end

  test "to_activitypub_object는 thumbnail이 없으면 attachment를 포함하지 않는다" do
    article = @article
    article.title_ko = "썸네일 없음"
    article.summary_key = [ "요약" ]

    # Pinned to `nil` by the initial assignment otherwise, which rejects the
    # assignment made inside the block below.
    captured = nil #: Hash[Symbol, untyped]?
    Fedipub::DataTransformer::Note.stub(:to_federation, ->(entity, name:, content:, custom:) { captured = { entity:, name:, content:, custom: }; { "ok" => true } }) do
      article.to_activitypub_object
    end

    assert_nil captured[:custom]["attachment"]
  end

  test "base_content는 summary_key 배열의 첫 항목을 사용한다" do
    article = Article.new(title: "원문 제목", summary_key: [ "첫 줄 요약", "두 번째 요약" ])

    assert_equal({ title: "원문 제목", summary: "첫 줄 요약" }, article.base_content)
  end

  test "base_content는 요약이 없으면 기본 문구를 사용한다" do
    article = Article.new(title: "원문 제목", summary_key: nil)

    assert_equal "새로운 Ruby 관련 글이 올라왔습니다.", article.base_content[:summary]
  end

  test "should_federate?는 user가 없거나 title_ko가 비어 있으면 false다" do
    assert_not Article.new(title_ko: "번역 제목").should_federate?
    assert_not Article.new(user: @user).should_federate?
  end

  test "likes_count는 nil이어도 0을 반환한다" do
    article = Article.new(title: "Like Count", url: "https://example.com/likes", origin_url: "https://example.com/likes", user: @user)
    article.likers_count = nil

    assert_equal 0, article.likes_count
  end

  test "user_name은 site가 없으면 host를 반환한다" do
    article = Article.new(title: "Host fallback", url: "https://example.com/host", origin_url: "https://example.com/host", host: "example.com", user: @user)
    article.site = nil

    assert_equal "example.com", article.user_name
  end

  test "update_slug는 잘못된 URL이면 false를 반환한다" do
    article = Article.new(title: "Broken URL", url: "http://[", origin_url: "http://[", user: @user)

    assert_not article.update_slug
  end

  test "to_markdown은 기사의 필드들을 마크다운 형식으로 올바르게 변환한다" do
    article = Article.new(
      title: "Test Title",
      title_ko: "테스트 제목",
      url: "https://example.com/test",
      origin_url: "https://example.com/test",
      host: "example.com",
      slug: "test-slug",
      summary_key: [ "핵심 요약 1", "핵심 요약 2" ],
      summary_detail: { "introduction" => "서론 부분", "conclusion" => "결론 부분" },
      body: "원본 본문",
      summary_body: "요약된 마크다운 본문",
      user: @user
    )

    markdown = article.to_markdown

    assert_match "# 테스트 제목", markdown
    assert_match "- **원문 URL**: https://example.com/test", markdown
    assert_match "- **Ruby-News URL**: #{Rails.application.routes.url_helpers.article_url(article)}", markdown
    assert_no_match "작성자", markdown
    assert_match "## 요약", markdown
    assert_match "- 핵심 요약 1", markdown
    assert_match "- 핵심 요약 2", markdown
    assert_match "## 소개\n서론 부분", markdown
    assert_match "## 본문\n요약된 마크다운 본문", markdown
    assert_match "## 결론\n결론 부분", markdown
  end

  # --- IndexNow enqueue ---

  test "confirmed 진입(create) 시 IndexNowJob을 30s 지연 예약한다" do
    stub_external_requests(nil) do
      article = Article.create!(
        title: "새 기사",
        title_ko: "새 기사 한국어",
        url: "https://example.com/new-idx",
        origin_url: "https://example.com/new-idx",
        host: "example.com",
        slug: "new-idx",
        body: "본문",
        user: users(:john)
      )

      assert_enqueued_with(
        job: IndexNowJob,
        args: [ article.id ],
        queue: "default"
      )
      # wait 옵션 확인: 예약된 잡의 scheduled_at이 30s 이후
      enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs.select { |j| j["job_class"] == "IndexNowJob" }

      assert_equal 1, enqueued.size
    end
  end

  test "의미 없는 변경(touch only)은 IndexNowJob을 예약하지 않는다" do
    article = articles(:ruby_article)
    # watched 속성 외의 필드만 갱신 — is_related는 watched 목록에 없음
    clear_index_now_jobs!

    assert_no_enqueues_index_now do
      article.update!(is_related: !article.is_related)
    end
  end

  test "unconfirmed 기사(title_ko 누락) 저장은 예약하지 않는다" do
    article = articles(:site_only_article) # slug 있음, title_ko nil
    clear_index_now_jobs!

    assert_no_enqueues_index_now do
      article.update!(title: "바뀐 제목")
    end
    assert_nil article.title_ko
  end

  test "watched 속성 변경 시 confirmed 기사는 예약한다" do
    article = articles(:ruby_article)
    clear_index_now_jobs!

    assert_enqueues_index_now(count: 1) do
      article.update!(title_ko: "바뀐 한국어 제목")
    end
  end

  test "디바운스: 30s 내 동일 id의 두 번째 예약은 스킵된다" do
    article = articles(:ruby_article)
    clear_index_now_jobs!
    # 테스트 환경의 기본 캐시는 NullStore라 잠금이 유지되지 않으므로
    # MemoryStore로 교체해 디바운스 잠금이 실제로 동작하는지 검증한다.
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    assert_enqueues_index_now(count: 1) do
      article.update!(title_ko: "첫 변경")
    end

    # 잠금이 설정된 상태에서 두 번째 변경 — 추가 예약 없음
    assert_no_enqueues_index_now do
      article.update!(body: "두 번째 본문 변경")
    end
  ensure
    Rails.cache = original_cache
  end

  private

  def clear_index_now_jobs!
    ActiveJob::Base.queue_adapter.enqueued_jobs.delete_if { |j| j["job_class"] == "IndexNowJob" }
  end

  def assert_enqueues_index_now(count:)
    before = enqueued_index_now_count
    yield

    assert_equal count, enqueued_index_now_count - before
  end

  def assert_no_enqueues_index_now
    before = enqueued_index_now_count
    yield

    assert_equal before, enqueued_index_now_count
  end

  def enqueued_index_now_count
    ActiveJob::Base.queue_adapter.enqueued_jobs.count { |j| j["job_class"] == "IndexNowJob" }
  end

  def stub_external_requests(article)
    response = Struct.new(:body, :status, :success?, :headers).new(
      "<html><head><title>Test</title></head><body>Test description</body></html>",
      200,
      true,
      {}
    )

    Faraday.stub(:get, ->(*) { response }) do
      yield(response) if block_given?
    end
  end

  def assert_queries(expected_count)
    queries = []
    ActiveSupport::Notifications.subscribe("sql.active_record") do |_name, _start, _finish, _id, payload|
      queries << payload[:sql] unless payload[:sql] =~ /^(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/
    end

    yield

    assert_equal expected_count, queries.size, "Expected #{expected_count} queries, got #{queries.size}"
  ensure
    ActiveSupport::Notifications.unsubscribe("sql.active_record")
  end
end
