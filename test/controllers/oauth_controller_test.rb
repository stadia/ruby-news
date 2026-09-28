# frozen_string_literal: true

require "test_helper"

class OauthControllerTest < ActionDispatch::IntegrationTest
  test "GET Slack install permits anonymous visitors" do
    Configs::Slack.stub(:configured?, true) do
      Configs::Slack.stub(:client_id, "configured-client") { get "/slack/install" }
    end

    assert_response :redirect
    assert_equal "slack.com", URI.parse(response.location).host
  end

  test "GET Slack install uses the configured client and scope" do
    Configs::Slack.stub(:configured?, true) do
      Configs::Slack.stub(:client_id, "configured-client") do
        Configs::Slack.stub(:install_scope, "incoming-webhook,chat:write") do
          get "/slack/install"
        end
      end
    end

    query = URI.decode_www_form(URI.parse(response.location).query).to_h

    assert_equal "configured-client", query.fetch("client_id")
    assert_equal "incoming-webhook,chat:write", query.fetch("scope")
    assert_equal slack_oauth_callback_url, query.fetch("redirect_uri")
    assert_match(/\A[0-9a-f]{32}\z/, query.fetch("state"))
  end

  test "GET Discord install permits anonymous visitors" do
    Configs::Discord.stub(:configured?, true) do
      Configs::Discord.stub(:client_id, "dc-123") { get "/discord/install" }
    end

    assert_response :redirect
    assert_equal "discord.com", URI.parse(response.location).host
  end

  test "GET result renders success page" do
    get "/slack/result?success=true&channel_name=general"

    assert_response :success
  end

  test "GET result renders error page" do
    get "/slack/result?success=false&error=access_denied"

    assert_response :success
  end

  test "GET install redirects with alert when Slack is not configured" do
    Configs::Slack.stub(:configured?, false) do
      get "/slack/install"

      assert_redirected_to oauth_result_path(provider: "slack", success: "false", error: I18n.t("oauth.errors.slack_not_configured"))
    end
  end

  test "GET install redirects with alert when Discord is not configured" do
    Configs::Discord.stub(:configured?, false) do
      get "/discord/install"

      assert_redirected_to oauth_result_path(provider: "discord", success: "false", error: I18n.t("oauth.errors.discord_not_configured"))
    end
  end

  test "GET install redirects with alert for unsupported provider" do
    get "/unknown/install"

    assert_redirected_to oauth_result_path(provider: "unknown", success: "false", error: "지원하지 않는 연동입니다.")
  end
end
