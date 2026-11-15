# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

# Rails Foundation의 On Rails는 한 에피소드를 공식 블로그·팟캐스트·YouTube로 함께 내고, 각각이
# 다른 수집원으로 들어와 기사가 여럿 생긴다(#1157). 제목·임베딩은 근거가 되지 못한다(같은 에피소드
# 쌍의 임베딩 유사도가 다른 에피소드 쌍보다 낮았다). 그래서 발행처가 남긴 구조적 근거로만 묶는다.
#   - 팟캐스트: URL의 에피소드 ID
#   - 블로그: 본문이 링크한 팟캐스트 에피소드
#   - YouTube(Rails 공식 채널): 설명문과 같은 문단을 가진 팟캐스트 피드 항목
module Articles::OnRailsEpisode
  KEY_PREFIX = "on_rails:"
  FEED_URL = "https://feeds.buzzsprout.com/2462975.rss"
  RAILS_YOUTUBE_CHANNEL_ID = "UC9zbLaqReIdoFfzdUbh13Nw"
  PODCAST_EPISODE = %r{\Ahttps://podcast\.rubyonrails\.org/\d+/episodes/(\d+)}
  BLOG_POST = %r{\Ahttps://rubyonrails\.org/\d{4}/\d+/\d+/on-rails-}
  # 설명문 앞부분만 비교한다. 뒤쪽의 프로그램 소개문은 모든 에피소드가 같아 근거가 되지 않는다.
  DESCRIPTION_HEAD = 400
  # 영상 설명은 피드의 링크를 URL·@핸들로 풀어 써서 글자 단위로 어긋난다. 그 차이를 넘어
  # 이만큼 연속으로 같은 구간이 있어야 같은 문단으로 본다.
  SHARED_RUN = 120

  class << self
    # 같은 에피소드 기사끼리 공유하는 키. 근거가 없으면 nil이다.
    # feed는 YouTube 기사일 때만 부른다(호출부가 한 번 읽은 피드를 여러 기사에 나눠 쓰도록).
    #: (Article article, ^() -> String feed) -> String?
    def key_for(article, feed)
      url = article.url.to_s
      id = if (episode_id = podcast_episode_id(url))
        episode_id
      elsif url.match?(BLOG_POST)
        linked_episode_id(SafeHttp.get_following_redirects(url).response.body.to_s)
      elsif article.is_youtube?
        youtube_episode_id(article.youtube_id, feed)
      end
      "#{KEY_PREFIX}#{id}" if id
    end

    #: (String? url) -> String?
    def podcast_episode_id(url)
      url.to_s[PODCAST_EPISODE, 1]
    end

    # 다른 에피소드도 함께 링크한 글은 어느 쪽인지 단정할 수 없어 nil이다.
    #: (String html) -> String?
    def linked_episode_id(html)
      only(Nokogiri::HTML5(html).css("a[href]").filter_map { podcast_episode_id(it["href"]) })
    end

    #: (String feed_xml, String description) -> String?
    def feed_episode_id(feed_xml, description)
      matches = Nokogiri::XML(feed_xml).xpath("//item").filter_map do |item|
        item_description = Nokogiri::HTML5.fragment(item.at_xpath("description")&.text.to_s).text
        item.at_xpath("guid")&.text.to_s[/\ABuzzsprout-(\d+)\z/, 1] if same_description?(description, item_description)
      end
      only(matches)
    end

    #: (String a, String b) -> bool
    def same_description?(a, b)
      head_a = description_head(a)
      head_b = description_head(b)
      (0..(head_a.size - SHARED_RUN)).any? { head_b.include?(head_a[it, SHARED_RUN].to_s) }
    end

    #: () -> String
    def fetch_feed
      SafeHttp.get_following_redirects(FEED_URL).response.body.to_s
    end

    private

    #: (String? video_id, ^() -> String feed) -> String?
    def youtube_episode_id(video_id, feed)
      return if video_id.blank?

      video = Yt::Video.new(id: video_id)
      return unless video.channel_id == RAILS_YOUTUBE_CHANNEL_ID

      feed_episode_id(feed.call, video.description.to_s)
    end

    #: (String text) -> String
    def description_head(text)
      text.gsub(%r{https?://\S+|@\w+}, "").downcase.gsub(/[^a-z0-9]/, "")[0, DESCRIPTION_HEAD].to_s
    end

    #: (Array[String] ids) -> String?
    def only(ids)
      ids.uniq.then { it.one? ? it.first : nil }
    end
  end
end
