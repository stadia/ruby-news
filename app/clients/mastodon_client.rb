# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

class MastodonClient
  attr_reader :client

  #: (oauth_config: untyped) -> void
  def initialize(oauth_config:)
    raise ArgumentError, "OAuth 설정이 비어있습니다: mastodon_oauth" if oauth_config.blank?
    raise ArgumentError, "액세스 토큰이 비어있습니다: mastodon_oauth" if oauth_config.access_token.blank?
    raise ArgumentError, "Mastodon 인스턴스 주소가 비어있습니다" if oauth_config.site.blank?

    @client = Faraday.new(url: oauth_config.site, request: { open_timeout: HttpTimeouts::OPEN, timeout: HttpTimeouts::REQUEST }) do |faraday|
      faraday.headers["Authorization"] = "Bearer #{oauth_config.access_token}"
      faraday.response :logger, nil, { bodies: true, log_level: :info }
      faraday.request :json
      faraday.response :json
    end
  end

  def post(text)
    response = client.post("api/v1/statuses", { status: text }.to_json)
    response
  end

  def delete(status_id)
    response = client.delete("api/v1/statuses/#{status_id}")
    response
  end
end
