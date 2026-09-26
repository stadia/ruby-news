# frozen_string_literal: true

require "test_helper"
require "uri"

class DiscordControllerTest < ActionDispatch::IntegrationTest
  test "anonymous callback still requires a valid install state" do
    refuse_code_exchange do
      get discord_oauth_callback_path, params: { code: "anonymous-code", state: "anonymous-state" }
    end

    assert_redirected_to oauth_result_path(provider: "discord", success: "false", error: I18n.t("oauth.errors.invalid_state"))
  end

  test "GET install redirects with alert when not configured" do
    Configs::Discord.stub(:configured?, false) do
      get "/discord/install"
    end

    assert_redirected_to oauth_result_path(provider: "discord", success: "false", error: I18n.t("oauth.errors.discord_not_configured"))
  end

  test "GET install redirects to Discord authorize url" do
    sign_in_as(users(:john))

    Configs::Discord.stub(:configured?, true) do
      Configs::Discord.stub(:client_id, "dc-123") do
        get "/discord/install"
      end
    end

    assert_response :redirect
    assert_includes response.location, "discord.com/api/oauth2/authorize"
    assert_includes response.location, "client_id=dc-123"
  end

  test "GET callback redirects to result when DiscordApiError occurs" do
    sign_in_as(users(:john))
    state = start_discord_install

    DiscordClient.stub(:exchange_code, ->(*) { raise DiscordClient::ApiError, "Token exchange failed" }) do
      get discord_oauth_callback_path, params: { code: "invalid-code", state: }
    end

    assert_redirected_to oauth_result_path(provider: "discord", success: "false", error: "연동을 완료하지 못했습니다. 잠시 후 다시 시도해 주세요.")
  end

  test "GET callback handles access_denied without exchanging a code" do
    sign_in_as(users(:john))
    state = start_discord_install

    refuse_code_exchange do
      get discord_oauth_callback_path, params: { error: "access_denied", state: }
    end

    assert_redirected_to oauth_result_path(provider: "discord", success: "false", error: "연동을 취소했습니다.")
    assert_nil DiscordChannel.find_by(remote_id: "G_SETUP")
  end

  test "GET callback hides other provider errors and skips code exchange" do
    sign_in_as(users(:john))
    state = start_discord_install

    refuse_code_exchange do
      get discord_oauth_callback_path, params: { error: "server_error", error_description: "secret upstream details", state: }
    end

    assert_redirected_to oauth_result_path(provider: "discord", success: "false", error: "연동을 완료하지 못했습니다. 잠시 후 다시 시도해 주세요.")
    refute_includes response.location, "secret upstream details"
  end

  test "GET callback rejects when state does not match the session" do
    sign_in_as(users(:john))
    start_discord_install

    refuse_code_exchange do
      get discord_oauth_callback_path, params: { code: "attacker-code", state: "mismatched-state" }
    end

    expect_invalid_state_rejection
  end

  test "GET callback rejects when session has no stored state" do
    sign_in_as(users(:john))

    refuse_code_exchange do
      get discord_oauth_callback_path, params: { code: "attacker-code", state: "any-state" }
    end

    expect_invalid_state_rejection
  end

  test "GET callback rejects when state is empty" do
    sign_in_as(users(:john))
    start_discord_install

    refuse_code_exchange do
      get discord_oauth_callback_path, params: { code: "attacker-code", state: "" }
    end

    expect_invalid_state_rejection
  end

  test "GET callback state cannot be reused after one callback" do
    sign_in_as(users(:john))
    state = start_discord_install

    DiscordClient.stub(:exchange_code, ->(*) { raise DiscordClient::ApiError, "invalid_code" }) do
      get discord_oauth_callback_path, params: { code: "first-code", state: }
    end

    refuse_code_exchange do
      get discord_oauth_callback_path, params: { code: "attacker-code", state: }
    end

    expect_invalid_state_rejection
  end

  test "GET callback rejects Slack install state" do
    sign_in_as(users(:john))
    Configs::Slack.stub(:configured?, true) { get "/slack/install" }
    slack_state = URI.decode_www_form(URI.parse(response.location).query).to_h.fetch("state")

    refuse_code_exchange do
      get discord_oauth_callback_path, params: { code: "attacker-code", state: slack_state }
    end

    expect_invalid_state_rejection
  end

  test "anonymous callback stores an approved discord channel" do
    state = start_discord_install

    oauth_response = {
      "access_token" => "bot-token-123",
      "guild" => { "id" => "G_SETUP", "name" => "Setup Guild" },
      "webhook" => {
        "guild_id" => "G_SETUP",
        "channel_id" => "C_PICK",
        "name" => "ruby-news",
        "url" => "https://discord.com/api/webhooks/123/whtoken"
      }
    }.with_indifferent_access

    with_approved_discord_target(oauth_response) do
      get discord_oauth_callback_path, params: { code: "code", state: state }
    end

    assert_redirected_to oauth_result_path(provider: "discord", success: "true", channel_name: "ruby-news")

    channel = DiscordChannel.find_by!(remote_id: "G_SETUP")

    assert_equal "Setup Guild", channel.name
    assert_equal "https://discord.com/api/webhooks/123/whtoken", channel.webhook_url
    assert_equal "C_PICK", channel.channel_id
    assert_equal "ruby-news", channel.channel_name
  end

  test "an existing guild cannot be redirected to another channel" do
    channel = DiscordChannel.create!(remote_id: "G_SETUP", name: "Old Guild", webhook_url: "https://discord.com/api/webhooks/old",
                                     channel_id: "COLD", channel_name: "old", status: :active)
    state = start_discord_install
    cleanup_urls = []
    oauth_response = {
      "guild" => { "id" => "G_SETUP", "name" => "New Guild" },
      "webhook" => { "guild_id" => "G_SETUP", "channel_id" => "CNEW", "name" => "new",
                     "url" => "https://discord.com/api/webhooks/124/newtoken" }
    }.with_indifferent_access

    with_approved_discord_target(oauth_response, channel_id: "CNEW", cleanup_urls:) do
      get discord_oauth_callback_path, params: { code: "new-code", state: }
    end

    assert_redirected_to oauth_result_path(provider: "discord", success: "false", error: I18n.t("oauth.errors.relink_not_allowed"))
    assert_equal channel.id, DiscordChannel.find_by!(remote_id: "G_SETUP").id
    assert_equal "https://discord.com/api/webhooks/old", channel.reload.webhook_url
    assert_equal [ "https://discord.com/api/webhooks/124/newtoken" ], cleanup_urls
  end

  test "GET callback fails when oauth response has no webhook" do
    sign_in_as(users(:john))

    state = start_discord_install

    oauth_response = {
      "access_token" => "oauth-token",
      "guild" => { "id" => "G_SETUP3", "name" => "Setup Guild" }
    }.with_indifferent_access
    with_approved_discord_target(oauth_response) do
      get discord_oauth_callback_path, params: { code: "code", state: state }
    end

    assert_redirected_to oauth_result_path(provider: "discord", success: "false", error: "Discord OAuth 응답에 webhook 정보가 없습니다.")
  end

  test "anonymous renewal of the same channel preserves inactive status" do
    channel = DiscordChannel.create!(remote_id: "G_SETUP", name: "Old", webhook_url: "https://example.com/old",
                                 channel_id: "CNEW", channel_name: "old", status: :inactive)
    state = start_discord_install

    with_approved_discord_target(approved_discord_oauth, channel_id: "CNEW") do
      get discord_oauth_callback_path, params: { code: "renew", state: }
    end

    assert_redirected_to oauth_result_path(provider: "discord", success: "true", channel_name: "new")
    assert_equal "https://discord.com/api/webhooks/124/newtoken", channel.reload.webhook_url
    assert_predicate channel, :inactive?
  end

  test "anonymous OAuth cannot restore a discarded channel" do
    channel = DiscordChannel.create!(remote_id: "G_SETUP", name: "Old", webhook_url: "https://example.com/old",
                                 channel_id: "CNEW", channel_name: "old", status: :active)
    channel.discard!
    state = start_discord_install

    with_approved_discord_target(approved_discord_oauth, channel_id: "CNEW") do
      get discord_oauth_callback_path, params: { code: "restore", state: }
    end

    assert_redirected_to oauth_result_path(provider: "discord", success: "false", error: I18n.t("oauth.errors.relink_not_allowed"))
    assert_predicate channel.reload, :discarded?
    assert_equal "https://example.com/old", channel.webhook_url
  end

  # 새 webhook URL은 공급자 토큰 응답에서 온 값이라, 공급자 형식이 맞으면
  # 확인에 실패해도 지워야 사용자 서버에 webhook이 쌓이지 않는다.
  test "mismatched provider verification cleans up the new webhook without creating a channel" do
    state = start_discord_install

    cleanup_urls = []
    with_approved_discord_target(approved_discord_oauth, guild_id: "OTHER", cleanup_urls:) do
      get discord_oauth_callback_path, params: { code: "mismatch", state: }
    end

    assert_redirected_to oauth_result_path(provider: "discord", success: "false", error: I18n.t("oauth.errors.provider_failure"))
    assert_nil DiscordChannel.find_by(remote_id: "G_SETUP")
    assert_equal [ approved_discord_oauth[:webhook][:url] ], cleanup_urls
  end

  test "a transient verification failure cleans up the new webhook" do
    state = start_discord_install
    cleanup_urls = []

    with_approved_discord_target(approved_discord_oauth, cleanup_urls:,
                                 verification: Struct.new(:success?, :status, :body).new(false, 429, "")) do
      get discord_oauth_callback_path, params: { code: "rate-limited", state: }
    end

    assert_redirected_to oauth_result_path(provider: "discord", success: "false", error: I18n.t("oauth.errors.provider_failure"))
    assert_equal [ approved_discord_oauth[:webhook][:url] ], cleanup_urls
  end

  test "a webhook URL outside Discord is never sent a cleanup request" do
    state = start_discord_install
    cleanup_urls = []
    oauth = approved_discord_oauth
    oauth[:webhook][:url] = "https://attacker.example/api/webhooks/124/newtoken"

    with_approved_discord_target(oauth, cleanup_urls:) do
      get discord_oauth_callback_path, params: { code: "foreign", state: }
    end

    assert_redirected_to oauth_result_path(provider: "discord", success: "false", error: I18n.t("oauth.errors.provider_failure"))
    assert_empty cleanup_urls
  end

  test "a concurrent first install that loses the unique race cleans up and fails softly" do
    # 다른 요청이 먼저 같은 길드를 저장한 상황: 이 요청은 조회 시점에 행을 보지 못했다.
    winner = DiscordChannel.create!(remote_id: "G_SETUP", name: "Winner", webhook_url: "https://discord.com/api/webhooks/9/wintoken",
                                    channel_id: "CNEW", channel_name: "winner", status: :active)
    state = start_discord_install
    cleanup_urls = []

    DiscordChannel.stub(:find_or_initialize_by, ->(*) { DiscordChannel.new(remote_id: "G_SETUP") }) do
      with_approved_discord_target(approved_discord_oauth, channel_id: "CNEW", cleanup_urls:) do
        get discord_oauth_callback_path, params: { code: "race", state: }
      end
    end

    assert_redirected_to oauth_result_path(provider: "discord", success: "false", error: I18n.t("oauth.errors.provider_failure"))
    assert_equal [ approved_discord_oauth[:webhook][:url] ], cleanup_urls
    assert_equal "https://discord.com/api/webhooks/9/wintoken", winner.reload.webhook_url
  end

  test "a response with a webhook but no guild cleans up the webhook and logs the shape" do
    state = start_discord_install
    cleanup_urls = []
    oauth = approved_discord_oauth.except(:guild)

    warnings = capture_warnings do
      with_approved_discord_target(oauth, cleanup_urls:) do
        get discord_oauth_callback_path, params: { code: "no-guild", state: }
      end
    end

    assert_redirected_to oauth_result_path(provider: "discord", success: "false", error: I18n.t("oauth.errors.discord_missing_webhook"))
    assert_equal [ approved_discord_oauth[:webhook][:url] ], cleanup_urls
    assert(warnings.any? { |message| message.include?("guild=false") })
    warnings.each { |message| refute_includes message, "newtoken" }
  end

  test "a rejected relink logs the reason and channel identifiers without the webhook token" do
    DiscordChannel.create!(remote_id: "G_SETUP", name: "Old", webhook_url: "https://discord.com/api/webhooks/1/oldtoken",
                           channel_id: "COLD", channel_name: "old", status: :active)
    state = start_discord_install

    warnings = capture_warnings do
      with_approved_discord_target(approved_discord_oauth, channel_id: "CNEW") do
        get discord_oauth_callback_path, params: { code: "relink", state: }
      end
    end

    rejection = warnings.find { |message| message.include?("relink rejected") }

    assert rejection, "relink 거절 로그가 남아야 합니다: #{warnings.inspect}"
    assert_includes rejection, "reason=channel_changed"
    assert_includes rejection, "existing_channel_id=COLD"
    assert_includes rejection, "incoming_channel_id=CNEW"
    refute_includes rejection, "newtoken"
  end

  test "GET callback checks state before handling a provider error" do
    state = start_discord_install

    refuse_code_exchange do
      get discord_oauth_callback_path, params: { error: "access_denied", state: "mismatched-state" }
    end

    expect_invalid_state_rejection

    refuse_code_exchange do
      get discord_oauth_callback_path, params: { error: "access_denied", state: }
    end

    expect_invalid_state_rejection
  end

  test "GET callback without code or error fails without exchanging a code" do
    state = start_discord_install

    warnings = capture_warnings do
      refuse_code_exchange do
        get discord_oauth_callback_path, params: { state: }
      end
    end

    assert_redirected_to oauth_result_path(provider: "discord", success: "false", error: I18n.t("oauth.errors.provider_failure"))
    assert(warnings.any? { |message| message.include?("code_present=false") })
  end

  test "GET callback logs provider errors other than a user cancellation" do
    state = start_discord_install

    warnings = capture_warnings do
      refuse_code_exchange do
        get discord_oauth_callback_path, params: { error: "invalid_scope", error_description: "scope not allowed", state: }
      end
    end

    assert(warnings.any? { |message| message.include?("invalid_scope") && message.include?("scope not allowed") })
  end

  test "rejected relink never deletes a webhook already stored by the site" do
    channel = DiscordChannel.create!(remote_id: "G_SETUP", name: "Old", webhook_url: approved_discord_oauth[:webhook][:url],
                                     channel_id: "COLD", channel_name: "old", status: :active)
    state = start_discord_install
    cleanup_urls = []

    with_approved_discord_target(approved_discord_oauth, channel_id: "CNEW", cleanup_urls:) do
      get discord_oauth_callback_path, params: { code: "rejected", state: }
    end

    assert_redirected_to oauth_result_path(provider: "discord", success: "false", error: I18n.t("oauth.errors.relink_not_allowed"))
    assert_empty cleanup_urls
    assert_equal "COLD", channel.reload.channel_id
  end

  private

  def approved_discord_oauth
    { "guild" => { "id" => "G_SETUP", "name" => "New Guild" },
      "webhook" => { "guild_id" => "G_SETUP", "channel_id" => "CNEW", "name" => "new",
                     "url" => "https://discord.com/api/webhooks/124/newtoken" } }.with_indifferent_access
  end


  def with_approved_discord_target(oauth_response, guild_id: "G_SETUP", channel_id: "C_PICK", cleanup_urls: [], verification: nil)
    webhook = oauth_response[:webhook] || {}
    body = { id: URI.parse(webhook[:url].to_s).path.split("/")[-2], guild_id:, channel_id:,
             application_id: "dc-123", type: 1 }.to_json
    response = verification || Struct.new(:success?, :status, :body).new(true, 200, body)
    Configs::Discord.stub(:client_id, "dc-123") do
      Faraday.stub(:get, ->(_url, &block) {
        request = Struct.new(:options).new(Struct.new(:open_timeout, :timeout).new)
        block.call(request)
        response
      }) do
        DiscordClient.stub(:delete_webhook, ->(url) { cleanup_urls << url; nil }) do
          DiscordClient.stub(:exchange_code, oauth_response) { yield }
        end
      end
    end
  end

  # 세션에 저장된 state를 얻으려면 install을 거쳐야 한다.
  def start_discord_install
    Configs::Discord.stub(:configured?, true) do
      Configs::Discord.stub(:client_id, "dc-123") do
        get "/discord/install"
      end
    end
    URI.decode_www_form(URI.parse(response.location).query).to_h.fetch("state")
  end

  # state 검증에 걸리면 토큰 교환까지 가면 안 된다. 호출되면 테스트를 실패시킨다.
  def refuse_code_exchange(&)
    DiscordClient.stub(:exchange_code, ->(*) { flunk "state 검증에 실패했는데 exchange_code가 호출됐습니다" }, &)
  end

  def expect_invalid_state_rejection
    assert_redirected_to oauth_result_path(provider: "discord", success: "false", error: I18n.t("oauth.errors.invalid_state"))
  end

  def capture_warnings(&)
    warnings = []
    DiscordController.logger.stub(:warn, ->(message = nil, &block) { warnings << (message || block&.call).to_s }, &)
    warnings
  end
end
