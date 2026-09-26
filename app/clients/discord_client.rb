# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

class DiscordClient
  class ApiError < StandardError; end

  AUTHORIZE_URL = "https://discord.com/api/oauth2/authorize" #: String
  TOKEN_URL = "https://discord.com/api/oauth2/token" #: String
  API_BASE = "https://discord.com/api/v10" #: String
  MANAGE_WEBHOOKS_PERMISSION = 536870912 #: Integer
  WEBHOOK_URL_PATTERN = %r{\Ahttps://discord\.com/api(?:/v10)?/webhooks/(\d+)/([A-Za-z0-9._-]+)\z} #: Regexp

  #: (DiscordChannel channel) -> void
  def initialize(channel)
    @channel = channel
  end

  #: (Hash[Symbol, untyped] embed_params) -> String?
  def post_embed(embed_params)
    webhook = Discordrb::Webhooks::Client.new(url: @channel.webhook_url)
    response = webhook.execute(nil, true) do |builder|
      builder.add_embed do |embed|
        embed.title = embed_params[:title]
        embed.url = embed_params[:url]
        embed.description = embed_params[:description]
        embed.colour = embed_params[:color] if embed_params[:color]
        if embed_params[:image_url].present?
          embed.image = Discordrb::Webhooks::EmbedImage.new(url: embed_params[:image_url])
        end
        if embed_params[:footer_text].present?
          embed.footer = Discordrb::Webhooks::EmbedFooter.new(text: embed_params[:footer_text])
        end
        embed.timestamp = embed_params[:timestamp] if embed_params[:timestamp]
      end
    end
    parsed = JSON.parse(response.body)
    parsed["id"]
  rescue RestClient::Exception => e
    raise ApiError, "#{e.class}: #{e.message}"
  rescue StandardError => e
    raise ApiError, "#{e.class}: #{e.message}"
  end

  class << self
    #: (redirect_uri: String, state: String) -> String
    def authorize_url(redirect_uri:, state:)
      query = {
        client_id: Configs::Discord.client_id,
        scope: "bot webhook.incoming",
        permissions: MANAGE_WEBHOOKS_PERMISSION,
        redirect_uri:,
        response_type: "code",
        state:
      }.to_query

      "#{AUTHORIZE_URL}?#{query}"
    end

    #: (String code, redirect_uri: String) -> ActiveSupport::HashWithIndifferentAccess
    def exchange_code(code, redirect_uri:)
      response = Faraday.post(TOKEN_URL) do |req|
        apply_timeouts(req)
        req.headers["Content-Type"] = "application/x-www-form-urlencoded"
        req.body = URI.encode_www_form(
          client_id: Configs::Discord.client_id,
          client_secret: Configs::Discord.client_secret,
          grant_type: "authorization_code",
          code:,
          redirect_uri:
        )
      end

      unless response.success?
        raise ApiError, "Discord OAuth 토큰 교환에 실패했습니다. HTTP #{response.status}"
      end

      parsed = parse_json(response.body)
      raise ApiError, "Invalid Discord OAuth response" unless parsed.is_a?(Hash)

      parsed.with_indifferent_access
    rescue Faraday::Error => e
      raise ApiError, "#{e.class}: #{e.message}"
    end

    #: (String webhook_url) -> void
    def delete_webhook(webhook_url)
      response = Faraday.delete(webhook_url) do |req|
        apply_timeouts(req)
      end

      return if response.success?

      raise ApiError, "Discord 웹훅 삭제에 실패했습니다. HTTP #{response.status}"
    rescue Faraday::Error => e
      raise ApiError, "#{e.class}: #{e.message}"
    end

    # Discord가 발급한 webhook URL인지 본다. 정리(DELETE) 요청은 이 형식의
    # URL로만 보내 임의 호스트로 요청이 나가지 않게 한다.
    #: (untyped url) -> bool
    def provider_webhook_url?(url)
      return false unless url.is_a?(String)

      WEBHOOK_URL_PATTERN.match?(url)
    end

    # OAuth 응답은 서버가 client_secret으로 TLS를 통해 직접 받은 값이므로
    # 이 조회가 위조 응답을 막지는 않는다. 저장 전에 webhook이 살아 있고
    # 이 앱이 승인한 서버·채널의 Incoming webhook인지 확인하는 방어 심층화다.
    # 실패 메시지는 운영 진단용이며 webhook 토큰을 담지 않는다.
    #: (Hash[untyped, untyped] oauth) -> void
    def verify_oauth_target!(oauth)
      guild = oauth[:guild]
      webhook = oauth[:webhook]
      validate_oauth_target!(guild, webhook)

      match = WEBHOOK_URL_PATTERN.match(webhook[:url])
      raise ApiError, "Invalid Discord webhook URL" unless match

      client_id = Configs::Discord.client_id.to_s
      raise ApiError, "Discord client_id is not configured" if client_id.blank?

      # 공급자 호스트에 고정한 URL로만 조회하며 리다이렉트를 따라가지 않는다.
      response = Faraday.get("#{API_BASE}/webhooks/#{match[1]}/#{match[2]}") { |req| apply_timeouts(req) }
      raise ApiError, "Discord webhook verification failed: HTTP #{response.status}" unless response.success?

      verified = parse_json(response.body)
      raise ApiError, "Invalid Discord webhook response" unless verified.is_a?(Hash)

      expected = { "id" => match[1], "type" => 1, "guild_id" => guild[:id],
                   "channel_id" => webhook[:channel_id], "application_id" => client_id }
      mismatched = expected.reject { |key, value| verified[key] == value }.keys
      raise ApiError, "Discord webhook target mismatch: #{mismatched.join(", ")}" if mismatched.any?
    rescue Faraday::Error => e
      raise ApiError, "Discord target verification failed: #{e.class}"
    end

    private

    #: (untyped guild, untyped webhook) -> void
    def validate_oauth_target!(guild, webhook)
      raise ApiError, "Invalid Discord OAuth target: guild, webhook" unless guild.is_a?(Hash) && webhook.is_a?(Hash)

      invalid = []
      invalid << "guild.id" unless guild[:id].is_a?(String) && guild[:id].present?
      invalid << "webhook.guild_id" unless webhook[:guild_id] == guild[:id]
      invalid << "webhook.channel_id" unless webhook[:channel_id].is_a?(String) && webhook[:channel_id].present?
      invalid << "webhook.url" unless webhook[:url].is_a?(String)
      raise ApiError, "Invalid Discord OAuth target: #{invalid.join(", ")}" if invalid.any?
    end

    #: (String body) -> untyped
    def parse_json(body)
      JSON.parse(body)
    rescue JSON::ParserError => e
      raise ApiError, "Discord API 응답 파싱에 실패했습니다: #{e.message}"
    end

    #: (untyped req) -> void
    def apply_timeouts(req)
      req.options.open_timeout = HttpTimeouts::OPEN
      req.options.timeout = HttpTimeouts::REQUEST
    end
  end
end
