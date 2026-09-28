# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

class TwitterClient
  attr_reader :client

  #: (oauth_config: untyped) -> void
  def initialize(oauth_config:)
    raise ArgumentError, "OAuth 설정이 비어있습니다: xcom_oauth" if oauth_config.blank?
    raise ArgumentError, "액세스 토큰이 비어있습니다: xcom_oauth" if oauth_config.access_token.blank?

    @client = Faraday.new(url: "https://api.x.com/2/", request: { open_timeout: HttpTimeouts::OPEN, timeout: HttpTimeouts::REQUEST }) do |faraday|
      faraday.headers["Authorization"] = "Bearer #{oauth_config.access_token}"
      faraday.response :logger, nil, { bodies: true, log_level: :info }
      faraday.request :json
      faraday.response :json
    end
  end

  def post(text)
    response = client.post("tweets", { text: text }.to_json)
    response
  end

  def delete(tweet_id)
    response = client.delete("tweets/#{tweet_id}")
    response
  end
end
