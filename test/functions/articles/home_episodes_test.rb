# frozen_string_literal: true

require "test_helper"

class Articles::HomeEpisodesTest < ActiveSupport::TestCase
  test "configured episodes have three source URLs with no URL shared across groups" do
    sources = Articles::HomeEpisodes::SOURCES
    sources.each do |urls|
      assert_kind_of Array, urls
      assert_equal 3, urls.size
    end
    urls = sources.flatten

    assert_equal urls.uniq.size, urls.size
  end

  test "keeps the newest eligible source and falls back when it is discarded" do
    announcement, podcast, video = episode_articles
    scope = Article.kept.confirmed.related

    assert_equal [ video.id ], Articles::HomeEpisodes.representatives(scope).where(id: [ announcement.id, podcast.id, video.id ]).pluck(:id)
    video.update_columns(deleted_at: Time.current)

    assert_equal [ podcast.id ], Articles::HomeEpisodes.representatives(scope).where(id: [ announcement.id, podcast.id ]).pluck(:id)
    podcast.update_columns(title_ko: nil)

    assert_includes Articles::HomeEpisodes.representatives(scope).pluck(:id), announcement.id
  end

  test "matches origin_url and leaves similarly titled unregistered URLs alone" do
    announcement, podcast, video = episode_articles
    video.update_columns(url: "https://www.youtube.com/watch?v=ko60zbx6dOE&feature=shared")
    separate = articles(:site_only_article)
    separate.update_columns(title: video.title, title_ko: video.title_ko, is_related: true, url: "https://www.therubyonrailspodcast.com/555", origin_url: "https://www.therubyonrailspodcast.com/555")

    ids = Articles::HomeEpisodes.representatives(Article.kept.confirmed.related).pluck(:id)

    assert_includes ids, video.id
    assert_includes ids, separate.id
    refute_includes ids, announcement.id
    refute_includes ids, podcast.id
    assert_equal [], Articles::HomeEpisodes.source_urls(separate)
  end

  test "verified sample episodes remain separate groups" do
    samples = [
      [ "https://rubyonrails.org/2026/8/18/on-rails-joanna-wang-sixfold", "https://www.youtube.com/watch?v=rMiaQiss6gY" ],
      [ "https://rubyonrails.org/2026/9/1/on-rails-kagen-hearn-and-eddie-galindo-ascend", "https://www.youtube.com/watch?v=YpiEcaVKrkQ" ],
      [ "https://rubyonrails.org/2026/10/22/on-rails-hussain-akram-and-antonio-carlos-de-souza-donorbox", "https://www.youtube.com/watch?v=3Y42uiA4tdE" ]
    ]
    articles = samples.flat_map.with_index do |urls, i|
      urls.map.with_index do |url, j|
        article = Article.new(user: users(:john), title: "On Rails", title_ko: "인터뷰", slug: "sample-#{i}-#{j}", url: url, origin_url: url, is_related: true, created_at: j.minutes.ago)
        article.stub(:generate_metadata, nil) { article.save! }
        article
      end
    end

    ids = Articles::HomeEpisodes.representatives(Article.where(id: articles.map(&:id))).pluck(:id)

    assert_equal articles.each_slice(2).map { |announcement, _| announcement.id }.sort, ids.sort
  end

  private

  def episode_articles
    [ articles(:ruby_article), articles(:korean_content_article), articles(:youtube_ruby_talk) ].zip([
      "https://rubyonrails.org/2026/11/13/on-rails-marco-roth-herb-reaction-view",
      "https://podcast.rubyonrails.org/2462975/episodes/20121188-marco-roth-teaching-rails-to-read-its-own-template",
      "https://www.youtube.com/watch?v=ko60zbx6dOE"
    ]).each_with_index.map do |(article, url), i|
      article.update_columns(url: url, origin_url: url, title_ko: "인터뷰", created_at: (3 - i).minutes.ago)
      article
    end
  end
end
