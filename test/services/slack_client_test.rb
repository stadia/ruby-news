# frozen_string_literal: true

require "test_helper"

class SlackClientTest < ActiveSupport::TestCase
  test "authorize_url은 빈 client_id로 승인 URL을 만들지 않는다" do
    [ nil, "", " \t" ].each do |client_id|
      assert_raises(SlackClient::ApiError) do
        SlackClient.authorize_url(client_id:, scope: "incoming-webhook", redirect_uri: "https://example.com/callback", state: "abc")
      end
    end
  end

  test "exchange_code는 빈 자격증명을 API 요청 전에 거부한다" do
    [ nil, "", " \t" ].each do |blank_value|
      [ { client_id: blank_value, client_secret: "secret" },
        { client_id: "client-123", client_secret: blank_value } ].each do |credentials|
        SlackClient.stub(:oauth_client, ->(*) { flunk "빈 자격증명으로 API를 호출했습니다" }) do
          assert_raises(SlackClient::ApiError) do
            SlackClient.exchange_code("code", **credentials, redirect_uri: "https://example.com/callback")
          end
        end
      end
    end
  end

  test "exchange_code는 SlackError와 Faraday timeout을 ApiError로 변환한다" do
    [ Slack::Web::Api::Errors::SlackError.new("invalid_code"), Faraday::TimeoutError.new("execution expired") ].each do |failure|
      api = Struct.new(:exception) do
        def oauth_v2_access(client_id:, client_secret:, code:, redirect_uri:)
          raise exception
        end
      end.new(failure)

      error = assert_raises(SlackClient::ApiError) do
        SlackClient.stub(:oauth_client, api) do
          SlackClient.exchange_code("code", client_id: "client-123", client_secret: "secret", redirect_uri: "https://example.com/callback")
        end
      end

      assert_includes error.message, failure.message
    end
  end

  test "authorization URL uses the supplied client and scope" do
    url = SlackClient.authorize_url(
      client_id: "injected-client", scope: "incoming-webhook,chat:write",
      redirect_uri: "https://example.com/slack/callback", state: "oauth-state"
    )
    uri = URI.parse(url)

    assert_equal "https://slack.com/oauth/v2/authorize", "#{uri.scheme}://#{uri.host}#{uri.path}"
    assert_equal({
      "client_id" => "injected-client", "scope" => "incoming-webhook,chat:write",
      "redirect_uri" => "https://example.com/slack/callback", "state" => "oauth-state"
    }, URI.decode_www_form(uri.query).to_h)
  end

  test "code exchange sends the supplied credentials and returns indifferent access" do
    api = Struct.new(:response) do
      def oauth_v2_access(client_id:, client_secret:, code:, redirect_uri:)
        unless [ client_id, client_secret, code, redirect_uri ] ==
               [ "injected-client", "injected-secret", "oauth-code", "https://example.com/slack/callback" ]
          raise ArgumentError, "Unexpected OAuth request parameters"
        end

        response
      end
    end.new({ "access_token" => "oauth-token", "team" => { "id" => "T123" } })

    response = SlackClient.stub(:oauth_client, api) do
      SlackClient.exchange_code(
        "oauth-code", client_id: "injected-client", client_secret: "injected-secret",
        redirect_uri: "https://example.com/slack/callback"
      )
    end

    assert_equal "oauth-token", response[:access_token]
    assert_equal "T123", response[:team][:id]
  end

  test "incoming webhook으로 메시지를 전송한다" do
    channel = notification_channels(:acme_slack)
    client = SlackClient.new(channel)
    response = Struct.new(:success?, :status).new(true, 200)
    webhook_client = Struct.new(:calls, :response) do
      def post
        request = Struct.new(:body).new
        yield request
        calls << request.body
        response
      end
    end.new([], response)

    client.stub(:webhook_client, webhook_client) do
      assert_equal({}, client.post_message(text: "hello", blocks: []))
    end

    assert_equal [ { text: "hello", blocks: [] } ], webhook_client.calls
  end

  test "Faraday 오류를 ApiError로 래핑한다" do
    channel = notification_channels(:acme_slack)
    client = SlackClient.new(channel)

    error = assert_raises(SlackClient::ApiError) do
      client.stub(:webhook_client, Struct.new(:exception) {
        def post
          raise exception
        end
      }.new(Faraday::TimeoutError.new("execution expired"))) do
        client.post_message(text: "hello", blocks: [])
      end
    end

    assert_includes error.message, "execution expired"
  end
  test "OAuth verification accepts the token workspace and approved webhook" do
    api = Struct.new(:response) { def auth_test = response }.new({ "team_id" => "T123" })

    SlackClient.stub(:oauth_client, api) { assert_nil SlackClient.verify_oauth_target!(approved_oauth) }
  end

  test "OAuth verification rejects a token for another workspace" do
    api = Struct.new(:response) { def auth_test = response }.new({ "team_id" => "OTHER" })

    SlackClient.stub(:oauth_client, api) do
      assert_raises(SlackClient::ApiError) { SlackClient.verify_oauth_target!(approved_oauth) }
    end
  end

  test "OAuth verification rejects unsafe webhook URLs before making API requests" do
    urls = [ "http://hooks.slack.com/services/T123/B123/token", "https://hooks.slack.com.attacker.test/services/T123/B123/token",
             "https://hooks.slack.com/services/T123/B123/token?redirect=evil", "https://user@hooks.slack.com/services/T123/B123/token" ]
    urls.each do |url|
      oauth = approved_oauth
      oauth["incoming_webhook"]["url"] = url

      SlackClient.stub(:oauth_client, ->(*) { flunk "Invalid webhook must not trigger verification requests" }) do
        assert_raises(SlackClient::ApiError) { SlackClient.verify_oauth_target!(oauth) }
      end
    end
  end

  test "OAuth verification rejects incomplete target information" do
    [ "access_token", "team", "incoming_webhook" ].each do |key|
      oauth = approved_oauth.except(key)
      assert_raises(SlackClient::ApiError) { SlackClient.verify_oauth_target!(oauth) }
    end
  end

  test "OAuth verification wraps Slack API errors with the error code" do
    api = Struct.new(:error) { def auth_test = raise(error) }.new(Slack::Web::Api::Errors::SlackError.new("invalid_auth"))

    SlackClient.stub(:oauth_client, api) do
      error = assert_raises(SlackClient::ApiError) { SlackClient.verify_oauth_target!(approved_oauth) }

      assert_includes error.message, "invalid_auth"
    end
  end

  test "OAuth verification wraps network errors" do
    api = Struct.new(:error) { def auth_test = raise(error) }.new(Faraday::TimeoutError.new("execution expired"))

    SlackClient.stub(:oauth_client, api) do
      error = assert_raises(SlackClient::ApiError) { SlackClient.verify_oauth_target!(approved_oauth) }

      assert_includes error.message, "Faraday::TimeoutError"
    end
  end

  test "OAuth verification names the invalid target fields" do
    oauth = approved_oauth
    oauth["incoming_webhook"]["channel_id"] = ""

    error = assert_raises(SlackClient::ApiError) { SlackClient.verify_oauth_target!(oauth) }

    assert_includes error.message, "incoming_webhook.channel_id"
    refute_includes error.message, "team.id"
  end

  private

  def approved_oauth
    { "access_token" => "oauth-token", "team" => { "id" => "T123" },
      "incoming_webhook" => { "channel_id" => "C123", "url" => "https://hooks.slack.com/services/T123/B123/token" } }
  end
end
