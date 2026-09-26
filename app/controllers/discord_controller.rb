# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

class DiscordController < ApplicationController
  include OauthStateVerification

  protect_from_forgery except: [ :callback ]

  def callback
    unless valid_oauth_state?(:discord_oauth_state)
      redirect_to oauth_result_path(provider: "discord", success: "false", error: t("oauth.errors.invalid_state"))
      return
    end

    if params[:error].present? || params[:code].blank?
      error_key = params[:error] == "access_denied" ? "oauth.errors.cancelled" : "oauth.errors.provider_failure"
      redirect_to oauth_result_path(provider: "discord", success: "false", error: t(error_key))
      return
    end

    oauth = DiscordClient.exchange_code(params[:code], redirect_uri: discord_oauth_callback_url)
    guild = oauth[:guild]
    webhook = oauth[:webhook]

    unless guild.present? && webhook.present?
      redirect_to oauth_result_path(provider: "discord", success: "false", error: t("oauth.errors.discord_missing_webhook"))
      return
    end

    guild_id = webhook[:guild_id].presence || guild[:id]
    webhook_url = webhook[:url]
    channel = DiscordChannel.find_or_initialize_by(remote_id: guild_id)
    channel.assign_attributes(
      name: guild[:name],
      webhook_url: webhook_url,
      channel_id: webhook[:channel_id],
      channel_name: webhook[:name].presence || "unknown",
      status: :active,
      last_verified_at: Time.current
    )

    begin
      DiscordChannel.transaction do
        channel.save!
      end
    rescue ActiveRecord::RecordInvalid
      cleanup_discord_webhook(webhook_url)
      raise
    end

    redirect_to oauth_result_path(provider: "discord", success: "true", channel_name: channel.channel_name)
  rescue DiscordClient::ApiError, ActiveRecord::RecordInvalid => e
    logger.warn("Discord OAuth callback failed: #{e.class}: #{e.message}")
    redirect_to oauth_result_path(provider: "discord", success: "false", error: t("oauth.errors.provider_failure"))
  end

  private

  def cleanup_discord_webhook(webhook_url)
    return if webhook_url.blank?

    DiscordClient.delete_webhook(webhook_url)
  rescue DiscordClient::ApiError => e
    logger.warn("Failed to cleanup Discord webhook #{webhook_url}: #{e.message}")
  end
end
