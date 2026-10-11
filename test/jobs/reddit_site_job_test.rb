# frozen_string_literal: true

require "test_helper"

class RedditSiteJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  MockMetadataResponse = Struct.new(:body, :status, :headers)

  test "RedditSiteJob은 ApplicationJob을 상속한다" do
    assert_includes RedditSiteJob.ancestors, ActiveJob::Base
  end

  test "REDDIT_HOSTS 상수가 정의되어 있다" do
    assert_includes RedditSiteJob::REDDIT_HOSTS, "reddit.com"
    assert_includes RedditSiteJob::REDDIT_HOSTS, "redd.it"
    assert_not_includes RedditSiteJob::REDDIT_HOSTS, "x.com"
  end

  test "external_link?가 Reddit 내부 도메인을 올바르게 식별한다" do
    job = RedditSiteJob.new

    # 외부 링크
    assert job.send(:external_link?, "https://example.com/article")
    assert job.send(:external_link?, "https://blog.rubyonrails.org/post")

    # Reddit 내부 도메인
    assert_not job.send(:external_link?, "https://www.reddit.com/r/ruby")
    assert_not job.send(:external_link?, "https://reddit.com/r/ruby")
    assert_not job.send(:external_link?, "https://old.reddit.com/r/ruby")
    assert_not job.send(:external_link?, "https://redd.it/abc123")

    # SNS 도메인은 external_link?에서 차단하지 않음 (Articles::Utils.should_ignore_url?이 처리)
    assert job.send(:external_link?, "https://x.com/dhh/status/123")
    assert job.send(:external_link?, "https://discord.com/invite/abc")

    # 빈 URL이나 nil
    assert_not job.send(:external_link?, "")
    assert_not job.send(:external_link?, nil)
  end

  test "external_link?가 잘못된 URL을 처리한다" do
    job = RedditSiteJob.new

    assert_not job.send(:external_link?, "not-a-url")
  end

  test "extract_external_links가 HTML 인코딩된 selftext에서 외부 링크를 추출한다" do
    job = RedditSiteJob.new

    html = "&lt;a href=\"https://example.com/post\"&gt;Link&lt;/a&gt; and &lt;a href=\"https://www.reddit.com/r/ruby\"&gt;Reddit&lt;/a&gt;"

    links = job.send(:extract_external_links, html)

    assert_includes links, "https://example.com/post"
    assert_not_includes links, "https://www.reddit.com/r/ruby"
  end

  test "extract_external_links가 nil을 처리한다" do
    job = RedditSiteJob.new

    assert_equal [], job.send(:extract_external_links, nil)
  end

  test "링크 포스트에서 외부 URL로 Article을 생성한다" do
    site = sites(:reddit)
    top_posts = [
      {
        "title" => "Great Ruby Article",
        "url" => "https://blog.example.com/ruby-tips",
        "is_self" => false,
        "created_utc" => 1.hour.ago.to_f
      }
    ]
    hot_posts = [
      {
        "title" => "Hot Ruby Post",
        "url" => "https://blog.example.com/hot-ruby",
        "is_self" => false,
        "created_utc" => 30.minutes.ago.to_f
      }
    ]
    call_count = 0
    mock_feed = ->(**kwargs) {
      call_count += 1
      kwargs[:sort] == :hot ? hot_posts : top_posts
    }

    with_stubbed_metadata_fetch do
      Reddit.stub(:feed, mock_feed) do
        assert_difference "Article.count", 2 do
          RedditSiteJob.new.perform
        end
      end
    end

    assert_equal 2, call_count
    article = Article.find_by(origin_url: "https://blog.example.com/ruby-tips")

    assert_equal "Great Ruby Article", article.title
    assert_equal site, article.site
    assert Article.exists?(origin_url: "https://blog.example.com/hot-ruby")
  end

  test "Reddit 내부 링크 포스트는 무시한다" do
    sites(:reddit)
    posts = [
      {
        "title" => "Discussion",
        "url" => "https://www.reddit.com/r/ruby/comments/abc123",
        "is_self" => false,
        "created_utc" => 1.hour.ago.to_f
      }
    ]

    Reddit.stub(:feed, ->(**) { posts }) do
      assert_no_difference "Article.count" do
        RedditSiteJob.new.perform
      end
    end
  end

  test "이미 존재하는 origin_url은 중복 생성하지 않는다" do
    site = sites(:reddit)
    existing_url = "https://blog.example.com/existing"
    with_stubbed_metadata_fetch do
      Article.create!(url: existing_url, origin_url: existing_url, site: site, user: User.first_bot)
    end

    posts = [
      {
        "title" => "Duplicate",
        "url" => existing_url,
        "is_self" => false,
        "created_utc" => 1.hour.ago.to_f
      }
    ]

    with_stubbed_metadata_fetch do
      Reddit.stub(:feed, ->(**) { posts }) do
        assert_no_difference "Article.count" do
          RedditSiteJob.new.perform
        end
      end
    end
  end

  test "Site가 없으면 아무 것도 하지 않는다" do
    Site.where(client: :reddit).delete_all

    feed_called = false
    mock_feed = ->(**) { feed_called = true; [] }

    Reddit.stub(:feed, mock_feed) do
      RedditSiteJob.new.perform
    end

    assert_not feed_called
  end

  test "self 포스트에서 본문의 외부 링크를 추출한다" do
    sites(:reddit)
    posts = [
      {
        "title" => "Useful Resources",
        "url" => "https://www.reddit.com/r/ruby/comments/xyz",
        "is_self" => true,
        "selftext_html" => "&lt;a href=\"https://thoughtbot.com/blog/ruby-tips\"&gt;Tips&lt;/a&gt;",
        "created_utc" => 1.hour.ago.to_f
      }
    ]

    with_stubbed_metadata_fetch do
      Reddit.stub(:feed, ->(**) { posts }) do
        assert_difference "Article.count", 1 do
          RedditSiteJob.new.perform
        end
      end
    end

    assert Article.exists?(origin_url: "https://thoughtbot.com/blog/ruby-tips")
  end

  private

  def with_stubbed_metadata_fetch(body = "<html><head><title>Fetched Title</title></head><body>Body</body></html>")
    response = MockMetadataResponse.new(body, 200, {})

    Articles::MetadataPreparation.stub(:fetch_url_content, ->(url) { SafeHttp::Fetched.new(response:, url:) }) do
      yield
    end
  end
end
