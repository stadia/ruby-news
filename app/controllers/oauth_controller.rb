# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

class OauthController < ApplicationController
  include WebOnlyFormats

  skip_before_action :authenticate_user!

  def install
    provider = params[:provider].presence || "slack"

    case provider
    when "slack"
      # slack
      unless Configs::Slack.configured?
        redirect_to oauth_result_path(provider:, success: "false", error: t("oauth.errors.slack_not_configured"))
        return
      end
    when "discord"
      # discord
      unless Configs::Discord.configured?
        redirect_to oauth_result_path(provider:, success: "false", error: t("oauth.errors.discord_not_configured"))
        return
      end
    else
      redirect_to oauth_result_path(provider:, success: "false", error: t("oauth.errors.unsupported_provider"))
      return
    end

    state = SecureRandom.hex(16)

    authorize_url = case provider
    when "slack"
      session[:slack_oauth_state] = state
      SlackClient.authorize_url(
        redirect_uri: slack_oauth_callback_url,
        state:
      )
    when "discord"
      session[:discord_oauth_state] = state
      DiscordClient.authorize_url(
        redirect_uri: discord_oauth_callback_url,
        state:
      )
    end

    redirect_to authorize_url, allow_other_host: true
  end

  def result
    @provider = params[:provider]
    @success = params[:success] == "true"
    @channel_name = params[:channel_name]
    @error = params[:error]
    render Views::Oauth::Result.new(
      provider: @provider,
      success: @success,
      channel_name: @channel_name,
      error: @error
    )
  end
end
