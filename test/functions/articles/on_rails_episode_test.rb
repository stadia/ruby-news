# frozen_string_literal: true

require "test_helper"

class Articles::OnRailsEpisodeTest < ActiveSupport::TestCase
  EPISODE_URL = "https://podcast.rubyonrails.org/2462975/episodes/20121188-marco-roth-teaching-rails-to-read-its-own-template"

  # 실제 On Rails 피드(feeds.buzzsprout.com/2462975.rss)의 두 항목을 줄인 것. 맨 뒤 소개문은 에피소드마다 같다.
  BOILERPLATE = "<p>On Rails is a podcast focused on real-world technical decision-making, exploring how teams are scaling, " \
                "architecting, and solving complex challenges with Rails. On Rails is brought to you by The Rails Foundation, " \
                "and hosted by Robby Russell of Planet Argon, a consultancy that helps teams improve and modernize their " \
                "existing Ruby on Rails apps.</p>"
  FEED = <<~XML
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0"><channel>
      <item>
        <title>Marco Roth: Teaching Rails to Read Its Own Template</title>
        <guid isPermaLink="false">Buzzsprout-20121188</guid>
        <description><![CDATA[<p>Marco Roth, an independent consultant and the creator of <a href='https://herb-tools.dev'><b>Herb</b></a><b> </b>and <a href='https://reactionview.dev'><b>ReActionView</b></a>, joins Robby to talk about teaching Rails to understand its own templates.</p><p>Marco explains how Herb parses HTML and ERB together, why that lets it catch broken views long before they reach production.</p>#{BOILERPLATE}]]></description>
      </item>
      <item>
        <title>DHH: Basecamp 5, Vibe Coding, and the Future of Rails</title>
        <guid isPermaLink="false">Buzzsprout-19335416</guid>
        <description><![CDATA[<p>David Heinemeier Hansson, creator of Ruby on Rails and co-owner of 37signals, joins Robby Russell the same week 37signals shipped Basecamp 5 to talk through the shift reshaping how software actually gets built today: why he reversed his stance on writing every line by hand.</p>#{BOILERPLATE}]]></description>
      </item>
    </channel></rss>
  XML

  # YouTube 설명은 피드의 링크를 URL·@핸들로 풀어 쓴다(실제 1JYTtAODjN8 설명).
  DHH_VIDEO_DESCRIPTION = "David Heinemeier Hansson @dhh37 , creator of Ruby on Rails and co-owner of @37signals, joins Robby Russell " \
                          "the same week 37signals shipped Basecamp 5 to talk through the shift reshaping how software actually " \
                          "gets built today: why he reversed his stance on writing every line by hand.\n\nLinks:\nhttps://dhh.dk"

  test "팟캐스트 에피소드 URL에서 에피소드 ID를 뽑는다" do
    assert_equal "20121188", Articles::OnRailsEpisode.podcast_episode_id(EPISODE_URL)
    assert_nil Articles::OnRailsEpisode.podcast_episode_id("https://podcast.rubyonrails.org")
    assert_nil Articles::OnRailsEpisode.podcast_episode_id("https://example.com/2462975/episodes/20121188-x")
  end

  test "블로그 본문이 가리키는 에피소드가 하나일 때만 그 ID를 돌려준다" do
    one = %(<p>Listen to <a href="#{EPISODE_URL}">this episode</a> or <a href="https://podcast.rubyonrails.org">subscribe</a>.</p>)
    two = %(<a href="#{EPISODE_URL}">a</a><a href="https://podcast.rubyonrails.org/2462975/episodes/19335416-dhh">b</a>)

    assert_equal "20121188", Articles::OnRailsEpisode.linked_episode_id(one)
    assert_equal "20121188", Articles::OnRailsEpisode.linked_episode_id(one + one)
    assert_nil Articles::OnRailsEpisode.linked_episode_id(two)
    assert_nil Articles::OnRailsEpisode.linked_episode_id("<p>no links</p>")
  end

  test "영상 설명과 같은 문단을 가진 피드 항목의 에피소드 ID를 찾는다" do
    assert_equal "19335416", Articles::OnRailsEpisode.feed_episode_id(FEED, DHH_VIDEO_DESCRIPTION)
  end

  test "공통 소개문만 겹치는 설명은 같은 에피소드로 보지 않는다" do
    other = "Brian Scanlan is a senior principal engineer at Intercom where he leads the platform group.\n\n" \
            "#{Nokogiri::HTML5.fragment(BOILERPLATE).text}"

    assert_nil Articles::OnRailsEpisode.feed_episode_id(FEED, other)
    assert_nil Articles::OnRailsEpisode.feed_episode_id(FEED, "")
  end

  test "팟캐스트 기사는 HTTP 요청 없이 키를 얻는다" do
    article = Article.new(url: EPISODE_URL)

    assert_equal "on_rails:20121188", Articles::OnRailsEpisode.key_for(article, -> { flunk "피드를 읽으면 안 된다" })
  end

  test "On Rails 블로그 기사는 본문이 링크한 에피소드로 키를 얻는다" do
    article = Article.new(url: "https://rubyonrails.org/2026/11/13/on-rails-marco-roth-herb-reaction-view")
    fetched = SafeHttp::Fetched.new(response: Struct.new(:status, :body).new(200, %(<a href="#{EPISODE_URL}">Listen</a>)), url: article.url)

    SafeHttp.stub(:get_following_redirects, fetched) do
      assert_equal "on_rails:20121188", Articles::OnRailsEpisode.key_for(article, -> { flunk "피드를 읽으면 안 된다" })
    end
  end

  test "Rails 공식 채널 영상은 피드에서 설명이 같은 에피소드로 키를 얻는다" do
    article = Article.new(url: "https://www.youtube.com/watch?v=1JYTtAODjN8", is_youtube: true)
    video = Struct.new(:channel_id, :description).new(Articles::OnRailsEpisode::RAILS_YOUTUBE_CHANNEL_ID, DHH_VIDEO_DESCRIPTION)

    Yt::Video.stub(:new, video) do
      assert_equal "on_rails:19335416", Articles::OnRailsEpisode.key_for(article, -> { FEED })
    end
  end

  test "다른 채널 영상과 관계없는 글은 키가 없다" do
    video = Struct.new(:channel_id, :description).new("UCother", DHH_VIDEO_DESCRIPTION)
    youtube = Article.new(url: "https://www.youtube.com/watch?v=BRDKft0-dUU", is_youtube: true)

    Yt::Video.stub(:new, video) do
      assert_nil Articles::OnRailsEpisode.key_for(youtube, -> { flunk "피드를 읽으면 안 된다" })
    end
    assert_nil Articles::OnRailsEpisode.key_for(Article.new(url: "https://rubyonrails.org/2026/11/13/rails-8-2-released"), -> { FEED })
  end
end
