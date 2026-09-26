# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

class SlackClient
  class ApiError < StandardError; end

  AUTHORIZE_URL = "https://slack.com/oauth/v2/authorize" #: String
  WEBHOOK_URL_PATTERN = %r{\Ahttps://hooks\.slack\.com/services/[A-Za-z0-9_-]+/[A-Za-z0-9_-]+/[A-Za-z0-9_-]+\z} #: Regexp

  # ── Instance methods ────────────────────────────────────

  #: (SlackChannel channel) -> void
  def initialize(channel)
    @channel = channel
  end

  #: (text: String, blocks: Array[untyped]) -> Hash[String, String]
  def post_message(text:, blocks:)
    response = webhook_client.post do |request|
      request.body = {
        text:,
        blocks:
      }
    end

    unless response.success?
      raise ApiError, "Slack webhook 전송에 실패했습니다. HTTP #{response.status}"
    end

    {}
  rescue Faraday::Error => e
    raise_api_error(e)
  end

  private

  #: SlackChannel
  attr_reader :channel

  # @rbs @webhook_client: Faraday::Connection?

  #: () -> Faraday::Connection
  def webhook_client
    @webhook_client ||= Faraday.new(url: channel.webhook_url) do |faraday|
      faraday.request :json
      faraday.response :raise_error
      faraday.adapter Faraday.default_adapter
    end
  end

  #: (Exception error) -> bot
  def raise_api_error(error)
    raise ApiError, "#{error.class}: #{error.message}"
  end

  class << self
    # ── OAuth (class methods) ──────────────────────────────

    #: (redirect_uri: String, state: String) -> String
    def authorize_url(redirect_uri:, state:)
      query = {
        client_id: Configs::Slack.client_id,
        scope: Configs::Slack.install_scope,
        redirect_uri:,
        state:
      }.to_query

      "#{AUTHORIZE_URL}?#{query}"
    end

    #: (String code, redirect_uri: String) -> ActiveSupport::HashWithIndifferentAccess
    def exchange_code(code, redirect_uri:)
      response = oauth_client.oauth_v2_access(
        client_id: Configs::Slack.client_id,
        client_secret: Configs::Slack.client_secret,
        code:,
        redirect_uri:
      )

      response.to_h.with_indifferent_access
    rescue Slack::Web::Api::Errors::SlackError => e
      raise ApiError, e.message
    rescue Faraday::Error => e
      raise ApiError, "#{e.class}: #{e.message}"
    end

    # 발급 토큰의 workspace를 Slack에 조회해 저장할 대상과 대조한다.
    # channel_id와 webhook URL은 같은 OAuth 응답에서만 가져온다.
    # OAuth 응답은 서버가 TLS로 직접 받은 값이라 위조 방지보다는 저장 전
    # 일관성 확인(방어 심층화)에 가깝다. 실패 메시지는 운영 진단용이며
    # 토큰과 webhook URL을 담지 않는다.
    #: (Hash[untyped, untyped] oauth) -> void
    def verify_oauth_target!(oauth)
      team = oauth["team"]
      webhook = oauth["incoming_webhook"]
      token = oauth["access_token"]
      invalid = invalid_oauth_target_fields(team, webhook, token)
      raise ApiError, "Invalid Slack OAuth target: #{invalid.join(", ")}" if invalid.any?

      identity = oauth_client(token).auth_test.to_h.with_indifferent_access
      raise ApiError, "Slack workspace mismatch" unless identity[:team_id] == team["id"]
    rescue Slack::Web::Api::Errors::SlackError, Faraday::Error => e
      # SlackError의 메시지는 invalid_auth 같은 오류 코드라 남겨도 안전하다.
      raise ApiError, "Slack target verification failed: #{e.class}: #{e.message}"
    end

    #: (?String? token) -> Slack::Web::Client
    def oauth_client(token = nil)
      Slack::Web::Client.new(
        token:,
        open_timeout: 3,
        timeout: 5
      )
    end

    private

    #: (untyped team, untyped webhook, untyped token) -> Array[String]
    def invalid_oauth_target_fields(team, webhook, token)
      team = {} unless team.is_a?(Hash)
      webhook = {} unless webhook.is_a?(Hash)

      invalid = []
      invalid << "access_token" unless token.is_a?(String) && token.present?
      invalid << "team.id" unless team["id"].is_a?(String) && team["id"].present?
      invalid << "incoming_webhook.channel_id" unless webhook["channel_id"].is_a?(String) && webhook["channel_id"].present?
      invalid << "incoming_webhook.url" unless webhook["url"].is_a?(String) && webhook["url"].match?(WEBHOOK_URL_PATTERN)
      invalid
    end
  end
end
