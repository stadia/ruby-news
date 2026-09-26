# frozen_string_literal: true

require "test_helper"

class OauthControllerTest < ActionDispatch::IntegrationTest
  test "GET Slack install permits anonymous visitors" do
    Configs::Slack.stub(:configured?, true) { get "/slack/install" }

    assert_response :redirect
    assert_equal "slack.com", URI.parse(response.location).host
  end

  test "GET Discord install permits anonymous visitors" do
    Configs::Discord.stub(:configured?, true) { get "/discord/install" }

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
