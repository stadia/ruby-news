# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

class DiscordController < ApplicationController
  include OauthStateVerification
  include OauthCallbackFailures

  protect_from_forgery except: [ :callback ]
  skip_before_action :authenticate_user!, only: :callback

  def callback
    unless valid_oauth_state?(:discord_oauth_state)
      redirect_to oauth_result_path(provider: "discord", success: "false", error: t("oauth.errors.invalid_state"))
      return
    end

    return if redirect_provider_error?("discord")

    # 토큰 교환이 성공하면 Discord는 이미 webhook을 만든 상태다. 이 뒤에서
    # 연동이 실패하면 새 webhook을 정리해 사용자 서버에 남지 않게 한다.
    oauth = DiscordClient.exchange_code(params[:code], redirect_uri: discord_oauth_callback_url)
    guild = oauth[:guild]
    webhook = oauth[:webhook]
    webhook_url = webhook.is_a?(Hash) ? webhook[:url] : nil

    unless guild.present? && webhook.present?
      logger.warn("Discord OAuth response is missing its target guild=#{guild.present?} webhook=#{webhook.present?}")
      cleanup_new_discord_webhook(webhook_url)
      redirect_to oauth_result_path(provider: "discord", success: "false", error: t("oauth.errors.discord_missing_webhook"))
      return
    end

    begin
      DiscordClient.verify_oauth_target!(oauth)
      channel = DiscordChannel.find_or_initialize_by(remote_id: guild[:id])
      channel.with_lock do
        channel.ensure_relink_allowed!(webhook[:channel_id])
        channel.assign_attributes(
          name: guild[:name],
          webhook_url: webhook_url,
          channel_id: webhook[:channel_id],
          channel_name: webhook[:name].presence || "unknown",
          last_verified_at: Time.current
        )
        channel.save!
      end
    rescue DiscordClient::ApiError, NotificationChannel::RelinkRejected, ActiveRecord::ActiveRecordError
      cleanup_new_discord_webhook(webhook_url)
      raise
    end

    redirect_to oauth_result_path(provider: "discord", success: "true", channel_name: channel.channel_name)
  rescue NotificationChannel::RelinkRejected => e
    redirect_relink_rejected("discord", e)
  rescue DiscordClient::ApiError, ActiveRecord::ActiveRecordError => e
    redirect_callback_failure("discord", e)
  end

  private

  # Discord 형식의 URL로만 DELETE를 보내고, 사이트가 이미 저장해 쓰는 webhook은 지우지 않는다.
  # 정리 실패는 원래 오류를 가리지 않도록 로그만 남긴다. 로그에는 토큰이 아닌 webhook id만 쓴다.
  #: (untyped webhook_url) -> void
  def cleanup_new_discord_webhook(webhook_url)
    return unless DiscordClient.provider_webhook_url?(webhook_url)
    return if DiscordChannel.exists?(webhook_url:)

    DiscordClient.delete_webhook(webhook_url)
  rescue DiscordClient::ApiError, ActiveRecord::ActiveRecordError => e
    webhook_id = DiscordClient::WEBHOOK_URL_PATTERN.match(webhook_url.to_s)&.[](1)
    logger.warn("Failed to cleanup Discord webhook id=#{webhook_id}: #{e.class}: #{e.message.to_s.gsub(webhook_url.to_s, "[FILTERED]")}")
  end
end
