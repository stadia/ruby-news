# frozen_string_literal: true

require "test_helper"
require "uri"

class SlackControllerTest < ActionDispatch::IntegrationTest
  test "anonymous callback still requires a valid install state" do
    refuse_code_exchange do
      get slack_oauth_callback_path, params: { code: "anonymous-code", state: "anonymous-state" }
    end

    assert_redirected_to oauth_result_path(provider: "slack", success: "false", error: I18n.t("oauth.errors.invalid_state"))
  end

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
    Configs::Slack.stub(:configured?, false) do
      get "/slack/install"
    end

    assert_redirected_to oauth_result_path(provider: "slack", success: "false", error: I18n.t("oauth.errors.slack_not_configured"))
  end

  test "GET callback redirects to failure result when code exchange fails" do
    sign_in_as(users(:john))
    state = start_slack_install

    SlackClient.stub(:exchange_code, ->(*) { raise SlackClient::ApiError, "invalid_code" }) do
      get slack_oauth_callback_path, params: { code: "invalid-code", state: }
    end

    assert_redirected_to oauth_result_path(provider: "slack", success: "false", error: "연동을 완료하지 못했습니다. 잠시 후 다시 시도해 주세요.")
  end

  test "GET callback handles access_denied without exchanging a code" do
    sign_in_as(users(:john))
    state = start_slack_install

    refuse_code_exchange do
      get slack_oauth_callback_path, params: { error: "access_denied", state: }
    end

    assert_redirected_to oauth_result_path(provider: "slack", success: "false", error: "연동을 취소했습니다.")
    assert_nil SlackChannel.find_by(remote_id: "TCALLBACK")
  end

  test "GET callback hides other provider errors and skips code exchange" do
    sign_in_as(users(:john))
    state = start_slack_install

    refuse_code_exchange do
      get slack_oauth_callback_path, params: { error: "server_error", error_description: "secret upstream details", state: }
    end

    assert_redirected_to oauth_result_path(provider: "slack", success: "false", error: "연동을 완료하지 못했습니다. 잠시 후 다시 시도해 주세요.")
    refute_includes response.location, "secret upstream details"
  end

  test "GET callback rejects when state does not match the session" do
    sign_in_as(users(:john))
    stored_state = start_slack_install

    expect_oauth_state_warning(:mismatch, secrets: [ stored_state, "mismatched-state" ]) do
      refuse_code_exchange do
        get slack_oauth_callback_path, params: { code: "attacker-code", state: "mismatched-state" }
      end
    end

    expect_invalid_state_rejection
  end

  test "GET callback rejects when session has no stored state" do
    sign_in_as(users(:john))

    expect_oauth_state_warning(:missing_session_state, secrets: [ "any-state" ]) do
      refuse_code_exchange do
        get slack_oauth_callback_path, params: { code: "attacker-code", state: "any-state" }
      end
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

  test "GET callback logs when request state is missing" do
    sign_in_as(users(:john))
    stored_state = start_slack_install

    expect_oauth_state_warning(:missing_param_state, secrets: [ stored_state ]) do
      refuse_code_exchange do
        get slack_oauth_callback_path, params: { code: "attacker-code" }
      end
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

  test "anonymous callback stores an approved slack channel" do
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

    with_approved_slack_target(oauth_response) do
      get slack_oauth_callback_path, params: { code: "oauth-code", state: state }
    end

    assert_redirected_to oauth_result_path(provider: "slack", success: "true", channel_name: "hada-news")

    channel = SlackChannel.find_by!(remote_id: "TCALLBACK")

    assert_equal "Callback Team", channel.name
    assert_equal "https://hooks.slack.com/services/TCALLBACK/B123/abc", channel.webhook_url
    assert_equal "CCALLBACK", channel.channel_id
    assert_equal "hada-news", channel.channel_name
  end

  test "an existing workspace cannot be redirected to another channel" do
    channel = SlackChannel.create!(remote_id: "TCALLBACK", name: "Old Team", webhook_url: "https://hooks.slack.com/services/old",
                                   channel_id: "COLD", channel_name: "old", status: :active)
    state = start_slack_install
    oauth_response = {
      "access_token" => "new-token",
      "team" => { "id" => "TCALLBACK", "name" => "New Team" },
      "incoming_webhook" => { "url" => "https://hooks.slack.com/services/TCALLBACK/BNEW/newtoken", "channel" => "new", "channel_id" => "CNEW" }
    }

    with_approved_slack_target(oauth_response) do
      get slack_oauth_callback_path, params: { code: "new-code", state: }
    end

    assert_redirected_to oauth_result_path(provider: "slack", success: "false", error: I18n.t("oauth.errors.relink_not_allowed"))
    assert_equal channel.id, SlackChannel.find_by!(remote_id: "TCALLBACK").id
    assert_equal "https://hooks.slack.com/services/old", channel.reload.webhook_url
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

  test "anonymous renewal of the same channel preserves inactive status" do
    channel = SlackChannel.create!(remote_id: "TCALLBACK", name: "Old", webhook_url: "https://example.com/old",
                                 channel_id: "CNEW", channel_name: "old", status: :inactive)
    state = start_slack_install

    with_approved_slack_target(approved_slack_oauth) do
      get slack_oauth_callback_path, params: { code: "renew", state: }
    end

    assert_redirected_to oauth_result_path(provider: "slack", success: "true", channel_name: "new")
    assert_equal "https://hooks.slack.com/services/TCALLBACK/BNEW/newtoken", channel.reload.webhook_url
    assert_predicate channel, :inactive?
  end

  test "anonymous OAuth cannot restore a discarded channel" do
    channel = SlackChannel.create!(remote_id: "TCALLBACK", name: "Old", webhook_url: "https://example.com/old",
                                 channel_id: "CNEW", channel_name: "old", status: :active)
    channel.discard!
    state = start_slack_install

    with_approved_slack_target(approved_slack_oauth) do
      get slack_oauth_callback_path, params: { code: "restore", state: }
    end

    assert_redirected_to oauth_result_path(provider: "slack", success: "false", error: I18n.t("oauth.errors.relink_not_allowed"))
    assert_predicate channel.reload, :discarded?
    assert_equal "https://example.com/old", channel.webhook_url
  end

  test "mismatched provider verification cannot create a channel" do
    state = start_slack_install

    with_approved_slack_target(approved_slack_oauth, team_id: "OTHER") do
      get slack_oauth_callback_path, params: { code: "mismatch", state: }
    end

    assert_redirected_to oauth_result_path(provider: "slack", success: "false", error: I18n.t("oauth.errors.provider_failure"))
    assert_nil SlackChannel.find_by(remote_id: "TCALLBACK")
  end

  private

  def approved_slack_oauth
    { "access_token" => "new-token", "team" => { "id" => "TCALLBACK", "name" => "New Team" },
      "incoming_webhook" => { "url" => "https://hooks.slack.com/services/TCALLBACK/BNEW/newtoken", "channel" => "new", "channel_id" => "CNEW" } }
  end


  def with_approved_slack_target(oauth_response, team_id: "TCALLBACK")
    api = Struct.new(:response) do
      def auth_test
        response
      end
    end.new({ "team_id" => team_id })
    SlackClient.stub(:oauth_client, api) do
      SlackClient.stub(:exchange_code, oauth_response) { yield }
    end
  end

  # 세션에 저장된 state를 얻으려면 install을 거쳐야 한다.
  def start_slack_install
    Configs::Slack.stub(:configured?, true) { get "/slack/install" }
    URI.decode_www_form(URI.parse(response.location).query).to_h.fetch("state")
  end

  # state 검증에 걸리면 토큰 교환까지 가면 안 된다. 호출되면 테스트를 실패시킨다.
  def refuse_code_exchange(&)
    SlackClient.stub(:exchange_code, ->(*) { flunk "state 검증에 실패했는데 exchange_code가 호출됐습니다" }, &)
  end

  def expect_oauth_state_warning(reason, secrets:)
    warnings = []
    SlackController.logger.stub(:warn, ->(message) { warnings << message }) { yield }

    assert_equal 1, warnings.size
    assert_includes warnings.first, reason.to_s
    assert_includes warnings.first, "slack_oauth_state"
    assert_includes warnings.first, "www.example.com"
    secrets.each { |secret| refute_includes warnings.first, secret }
  end

  def expect_invalid_state_rejection
    assert_redirected_to oauth_result_path(provider: "slack", success: "false", error: I18n.t("oauth.errors.invalid_state"))
    assert_nil SlackChannel.find_by(remote_id: "TCALLBACK")
  end
end
