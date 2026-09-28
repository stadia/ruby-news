# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

class TwitterService < SocialMediaService
  TwitterConfig = Data.define(:character_limit, :shortened_url_length, :formatting_buffer)

  class TwitterConfig
    #: () -> Integer
    def max_content_length = character_limit - shortened_url_length - formatting_buffer
  end

  TWITTER_CONFIG = TwitterConfig.new(280, 23, 4) #: TwitterConfig

  private

  #: () -> String
  def platform_name
    "X.com"
  end

  #: (Article article) -> Dry::Monads::Result
  def post_to_platform(article)
    return Failure(:already_posted) if article.twitter_id.present?

    post_text = build_post_text(article)
    response = platform_client.post(post_text)

    if response.status < 200 || response.status > 299
      logger.error "Failed to post to #{platform_name} for article id: #{article.id} - Status: #{response.status}"
      return Failure(response.status)
    end

    twitter_id = response.body["data"]["id"]
    article.update(twitter_id:)
    logger.info "Successfully posted to #{platform_name} for article id: #{article.id} - SocialId: #{twitter_id}"
    Success(twitter_id)
  end

  #: (Article article) -> Dry::Monads::Result
  def delete_from_platform(article)
    unless article.twitter_id.present?
      logger.info "Skipping #{platform_name} delete for article id: #{article.id} - no twitter_id"
      return Failure(:no_social_id)
    end

    response = platform_client.delete(article.twitter_id)

    if response.status < 200 || response.status > 299
      logger.error "Failed to delete from #{platform_name} for article id: #{article.id} - Status: #{response.status}"
      return Failure(response.status)
    end

    article.update(twitter_id: nil)
    logger.info "Successfully deleted from #{platform_name} for article id: #{article.id}"
    Success(article.id)
  end

  #: (Article article) -> String
  def build_post_text(article)
    content_data = article.base_content
    content = "#{content_data[:title]}\n#{content_data[:summary]}"

    # 태그와 링크를 먼저 생성해서 길이 계산 (taggings_count가 가장 높은 태그 하나만)
    top_tag = article.tags.select { |it| it.is_confirmed? }.max_by { |it| it.taggings_count.to_i }
    tags = top_tag ? "##{top_tag.name.to_s.gsub(/\s+/, '_').downcase}" : ""
    link = article_link(article.slug.to_s)

    # 태그와 링크를 위한 공간 확보 (공백 문자들 포함)
    reserved_space = tags.length + link.length + 3 # " " + "\n" + 여분
    available_content_length = TWITTER_CONFIG.max_content_length - reserved_space

    truncated_content = content.truncate([ available_content_length, 1 ].max, omission: "...")
    "#{truncated_content} #{tags}\n#{link}"
  end

  #: () -> TwitterClient
  def platform_client
    oauth_config = Preference.get_object("xcom_oauth")
    raise ArgumentError, "OAuth 설정이 비어있습니다: xcom_oauth" if oauth_config.nil?
    raise ArgumentError, "액세스 토큰이 비어있습니다: xcom_oauth" if oauth_config.access_token.blank?

    refresh_token_if_expired(oauth_config)
    TwitterClient.new(oauth_config:)
  end

  #: (Preference config) -> void
  def refresh_token_if_expired(config)
    token = OAuth2::AccessToken.from_hash(OauthClient.build(config), {
      access_token: config.access_token,
      refresh_token: config.refresh_token,
      expires_at: config.expires_at
    })
    return unless token.expired?

    token = token.refresh!
    config.update(access_token: token.token,
      refresh_token: token.refresh_token,
      expires_at: token.expires_at
    )
  end
end
