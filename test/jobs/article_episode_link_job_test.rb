# frozen_string_literal: true

require "test_helper"

class ArticleEpisodeLinkJobTest < ActiveSupport::TestCase
  test "최근에 수집한 키 없는 후보 기사에 에피소드 키를 붙인다" do
    recent = create_article!("https://podcast.rubyonrails.org/2462975/episodes/20121188-marco-roth")
    old = create_article!("https://podcast.rubyonrails.org/2462975/episodes/19335416-dhh", created_at: 3.days.ago)
    keyed = create_article!("https://podcast.rubyonrails.org/2462975/episodes/19665210-joanna", episode_key: "on_rails:1")

    ArticleEpisodeLinkJob.perform_now

    assert_equal "on_rails:20121188", recent.reload.episode_key
    assert_nil old.reload.episode_key
    assert_equal "on_rails:1", keyed.reload.episode_key

    ArticleEpisodeLinkJob.perform_now(7)

    assert_equal "on_rails:19335416", old.reload.episode_key
  end

  test "한 기사의 네트워크 오류는 기록하고 다음 기사를 계속 처리한다" do
    blog = create_article!("https://rubyonrails.org/2026/11/13/on-rails-marco-roth-herb-reaction-view")
    podcast = create_article!("https://podcast.rubyonrails.org/2462975/episodes/20121188-marco-roth")

    SafeHttp.stub(:get_following_redirects, ->(_url) { raise Faraday::ConnectionFailed, "down" }) do
      assert_nothing_raised { ArticleEpisodeLinkJob.perform_now }
    end

    assert_nil blog.reload.episode_key
    assert_equal "on_rails:20121188", podcast.reload.episode_key
  end

  private

  def create_article!(url, **attributes)
    article = Article.new(url:, title: url, user: users(:john), is_related: true, **attributes)
    article.stub(:generate_metadata, nil) { article.save! }
    article
  end
end
