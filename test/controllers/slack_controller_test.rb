# frozen_string_literal: true

require "test_helper"
require "uri"

class SlackControllerTest < ActionDispatch::IntegrationTest
  test "POST events rejects when signing secret is blank" do
    Configs::Slack.stub(:signing_secret, "") do
      post slack_events_path,
        params: { type: "url_verification", challenge: "challenge-token" },
        headers: {
          "X-Slack-Request-Timestamp" => Time.now.to_i.to_s,
          "X-Slack-Signature" => "v0=test"
        }
    end

    assert_response :unauthorized
  end

  test "GET install redirects to slack authorize url" do
    sign_in_as(users(:john))

    Configs::Slack.stub(:configured?, true) do
      Configs::Slack.stub(:client_id, "client-123") do
        get "/slack/install"
      end
    end

    assert_response :redirect
    assert_includes response.location, "https://slack.com/oauth/v2/authorize"
    assert_includes response.location, "client_id=client-123"
    scopes = URI.decode_www_form(URI.parse(response.location).query).to_h.fetch("scope")

    assert_equal "incoming-webhook", scopes
  end

  test "GET install redirects with alert when not configured" do
    sign_in_as(users(:john))

    Configs::Slack.stub(:configured?, false) do
      get "/slack/install"
    end

    assert_redirected_to edit_user_registration_path
    assert_equal "Slack 연동이 아직 설정되지 않았습니다. 관리자에게 문의해 주세요.", flash[:alert]
  end

  test "GET callback redirects to failure result when code exchange fails" do
    sign_in_as(users(:john))
    state = start_slack_install

    SlackClient.stub(:exchange_code, ->(*) { raise SlackClient::ApiError, "invalid_code" }) do
      get slack_oauth_callback_path, params: { code: "invalid-code", state: }
    end

    assert_redirected_to oauth_result_path(provider: "slack", success: "false", error: "invalid_code")
  end

  test "GET callback rejects when state does not match the session" do
    sign_in_as(users(:john))
    start_slack_install

    refuse_code_exchange do
      get slack_oauth_callback_path, params: { code: "attacker-code", state: "mismatched-state" }
    end

    expect_invalid_state_rejection
  end

  test "GET callback rejects when session has no stored state" do
    sign_in_as(users(:john))

    refuse_code_exchange do
      get slack_oauth_callback_path, params: { code: "attacker-code", state: "any-state" }
    end

    expect_invalid_state_rejection
  end

  test "GET callback rejects when both state values are empty" do
    sign_in_as(users(:john))

    refuse_code_exchange do
      get slack_oauth_callback_path, params: { code: "attacker-code", state: "" }
    end

    expect_invalid_state_rejection
  end

  test "GET callback state cannot be reused after one callback" do
    sign_in_as(users(:john))
    state = start_slack_install

    SlackClient.stub(:exchange_code, ->(*) { raise SlackClient::ApiError, "invalid_code" }) do
      get slack_oauth_callback_path, params: { code: "first-code", state: }
    end

    refuse_code_exchange do
      get slack_oauth_callback_path, params: { code: "attacker-code", state: }
    end

    expect_invalid_state_rejection
  end

  test "GET callback stores workspace webhook configuration and redirects to result page" do
    sign_in_as(users(:john))

    state = start_slack_install

    oauth_response = {
      "team" => { "id" => "TCALLBACK", "name" => "Callback Team" },
      "access_token" => "xoxb-callback",
      "bot_user_id" => "UBOTCALLBACK",
      "incoming_webhook" => {
        "url" => "https://hooks.slack.com/services/TCALLBACK/B123/abc",
        "channel" => "hada-news",
        "channel_id" => "CCALLBACK"
      }
    }

    SlackClient.stub(:exchange_code, oauth_response) do
      get slack_oauth_callback_path, params: { code: "oauth-code", state: state }
    end

    assert_redirected_to oauth_result_path(provider: "slack", success: "true", channel_name: "hada-news")

    channel = SlackChannel.find_by!(remote_id: "TCALLBACK")

    assert_equal "Callback Team", channel.name
    assert_equal "https://hooks.slack.com/services/TCALLBACK/B123/abc", channel.webhook_url
    assert_equal "CCALLBACK", channel.channel_id
    assert_equal "hada-news", channel.channel_name
  end

  test "POST events accepts url verification without login when signature is valid" do
    timestamp = Time.now.to_i.to_s
    payload = { type: "url_verification", challenge: "challenge-token" }
    raw_body = payload.to_json
    signature = "v0=" + OpenSSL::HMAC.hexdigest("SHA256", "signing-secret", "v0:#{timestamp}:#{raw_body}")

    Configs::Slack.stub(:signing_secret, "signing-secret") do
      post slack_events_path,
        params: raw_body,
        headers: {
          "CONTENT_TYPE" => "application/json",
          "X-Slack-Request-Timestamp" => timestamp,
          "X-Slack-Signature" => signature
        }
    end

    assert_response :success
    assert_equal "challenge-token", response.parsed_body["challenge"]
  end

  private

  # 세션에 저장된 state를 얻으려면 install을 거쳐야 한다.
  def start_slack_install
    Configs::Slack.stub(:configured?, true) { get "/slack/install" }
    URI.decode_www_form(URI.parse(response.location).query).to_h.fetch("state")
  end

  # state 검증에 걸리면 토큰 교환까지 가면 안 된다. 호출되면 테스트를 실패시킨다.
  def refuse_code_exchange(&)
    SlackClient.stub(:exchange_code, ->(*) { flunk "state 검증 전에 exchange_code가 호출됐습니다" }, &)
  end

  def expect_invalid_state_rejection
    assert_redirected_to oauth_result_path(provider: "slack", success: "false", error: I18n.t("oauth.errors.invalid_state"))
    assert_nil SlackChannel.find_by(remote_id: "TCALLBACK")
  end
end
