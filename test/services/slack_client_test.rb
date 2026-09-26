# frozen_string_literal: true

require "test_helper"

class SlackClientTest < ActiveSupport::TestCase
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

  private

  def approved_oauth
    { "access_token" => "oauth-token", "team" => { "id" => "T123" },
      "incoming_webhook" => { "channel_id" => "C123", "url" => "https://hooks.slack.com/services/T123/B123/token" } }
  end
end
