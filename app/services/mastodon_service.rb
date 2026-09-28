# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

class MastodonService < SocialMediaService
  MastodonConfig = Data.define(:character_limit, :url_length_counted, :formatting_buffer)

  class MastodonConfig
    #: () -> Integer
    def max_content_length = character_limit - formatting_buffer
  end

  # Mastodon의 기본 문자 제한은 500자 (인스턴스마다 다를 수 있음)
  # URL은 실제 길이가 카운트됨 (Twitter와 다름)
  MASTODON_CONFIG = MastodonConfig.new(500, true, 10) #: MastodonConfig

  private

  #: () -> String
  def platform_name
    "Mastodon"
  end

  #: (Article article) -> Dry::Monads::Result
  def post_to_platform(article)
    return Failure(:already_posted) if article.mastodon_id.present?

    post_text = build_post_text(article)
    response = platform_client.post(post_text)
    if response.status < 200 || response.status > 299
      logger.error "Failed to post to #{platform_name} for article id: #{article.id} - Status: #{response.status}"
      return Failure(response.status)
    end

    mastodon_id = response.body["id"]
    article.update(mastodon_id:)
    logger.info "Successfully posted to #{platform_name} for article id: #{article.id} - SocialId: #{mastodon_id}"
    Success(mastodon_id)
  end

  #: (Article article) -> Dry::Monads::Result
  def delete_from_platform(article)
    unless article.mastodon_id.present?
      logger.info "Skipping #{platform_name} delete for article id: #{article.id} - no mastodon_id"
      return Failure(:no_social_id)
    end

    response = platform_client.delete(article.mastodon_id)
    if response.status < 200 || response.status > 299
      logger.error "Failed to delete from #{platform_name} for article id: #{article.id} - Status: #{response.status}"
      return Failure(response.status)
    end

    article.update(mastodon_id: nil)
    logger.info "Successfully deleted from #{platform_name} for article id: #{article.id}"
    Success(article.id)
  end

  #: (Article article) -> String
  def build_post_text(article)
    content_data = article.base_content
    content = "#{content_data[:title]}\n\n#{content_data[:summary]}"

    # Mastodon은 여러 태그를 지원하므로 상위 3개 태그 사용
    top_tags = article.tags.select { |it| it.is_confirmed? }
                           .sort_by { |it| it.taggings_count.to_i }
                           .reverse
                           .take(3)
    tags = top_tags.map { |tag| "##{tag.name.to_s.gsub(/\s+/, '_').downcase}" }.join(" ")
    link = article_link(article.slug.to_s)

    # Mastodon은 URL을 실제 길이로 계산하므로 링크 길이도 포함
    reserved_space = tags.length + link.length + 5 # 공백과 줄바꿈
    available_content_length = MASTODON_CONFIG.max_content_length - reserved_space

    truncated_content = content.truncate([ available_content_length, 1 ].max, omission: "...")
    "#{truncated_content}\n\n#{tags}\n#{link}"
  end

  #: () -> MastodonClient
  def platform_client
    MastodonClient.new(oauth_config: Preference.get_object("mastodon_oauth"))
  end
end
