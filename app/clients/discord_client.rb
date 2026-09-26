# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

class DiscordClient
  class ApiError < StandardError; end

  AUTHORIZE_URL = "https://discord.com/api/oauth2/authorize" #: String
  TOKEN_URL = "https://discord.com/api/oauth2/token" #: String
  API_BASE = "https://discord.com/api/v10" #: String
  MANAGE_WEBHOOKS_PERMISSION = 536870912 #: Integer

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

    #: (Hash[untyped, untyped] oauth) -> void
    def verify_oauth_target!(oauth)
      guild = oauth[:guild]
      webhook = oauth[:webhook]
      validate_oauth_target!(guild, webhook)

      match = %r{\Ahttps://discord\.com/api(?:/v10)?/webhooks/(\d+)/([A-Za-z0-9._-]+)\z}.match(webhook[:url])
      raise ApiError, "Invalid Discord webhook URL" unless match

      # 공급자 호스트에 고정한 URL로만 조회하며 리다이렉트를 따라가지 않는다.
      response = Faraday.get("#{API_BASE}/webhooks/#{match[1]}/#{match[2]}") { |req| apply_timeouts(req) }
      raise ApiError, "Discord webhook verification failed" unless response.success?

      verified = parse_json(response.body)
      expected = { "id" => match[1], "type" => 1, "guild_id" => guild[:id],
                   "channel_id" => webhook[:channel_id], "application_id" => Configs::Discord.client_id }
      unless Configs::Discord.client_id.present? && verified.is_a?(Hash) && expected.all? { |key, value| verified[key] == value }
        raise ApiError, "Discord webhook target mismatch"
      end
    rescue Faraday::Error => e
      raise ApiError, "Discord target verification failed: #{e.class}"
    end

    private

    #: (untyped guild, untyped webhook) -> void
    def validate_oauth_target!(guild, webhook)
      unless guild.is_a?(Hash) && webhook.is_a?(Hash) &&
          guild[:id].is_a?(String) && guild[:id].present? && webhook[:guild_id] == guild[:id] &&
          webhook[:channel_id].is_a?(String) && webhook[:channel_id].present? && webhook[:url].is_a?(String)
        raise ApiError, "Invalid Discord OAuth target"
      end
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
