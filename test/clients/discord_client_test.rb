# frozen_string_literal: true

require "test_helper"

class DiscordClientTest < ActiveSupport::TestCase
  test "post_embed는 Discord webhook으로 embed를 전송하고 message id를 반환한다" do
    channel = notification_channels(:acme_discord)
    client = DiscordClient.new(channel)

    response_body = { "id" => "msg-123", "content" => "" }.to_json
    fake_response = Struct.new(:body).new(response_body)

    fake_webhook = Struct.new(:response) do
      def execute(_builder, _wait, &block)
        response
      end
    end.new(fake_response)

    Discordrb::Webhooks::Client.stub(:new, fake_webhook) do
      result = client.post_embed(title: "Test", url: "https://example.com", description: "desc", color: 3447003)

      assert_equal "msg-123", result
    end
  end

  test "post_embed는 RestClient 오류를 ApiError로 래핑한다" do
    channel = notification_channels(:acme_discord)
    client = DiscordClient.new(channel)

    fake_webhook = Struct.new(:exception) do
      def execute(*, &)
        raise exception
      end
    end.new(RestClient::Forbidden.new)

    error = assert_raises(DiscordClient::ApiError) do
      Discordrb::Webhooks::Client.stub(:new, fake_webhook) do
        client.post_embed(title: "Test", url: "https://example.com")
      end
    end

    assert_includes error.message, "RestClient::Forbidden"
  end

  test "authorize_url은 Discord OAuth URL을 생성한다" do
    Configs::Discord.stub(:client_id, "dc-123") do
      url = DiscordClient.authorize_url(redirect_uri: "https://example.com/callback", state: "abc")

      assert_includes url, "discord.com/api/oauth2/authorize"
      assert_includes url, "client_id=dc-123"
      assert_includes url, "state=abc"
      assert_includes url, "scope=bot+webhook.incoming"
    end
  end

  test "exchange_code는 Faraday 오류를 ApiError로 래핑한다" do
    faraday_error = Faraday::ConnectionFailed.new("connection refused")

    Configs::Discord.stub(:client_id, "dc-123") do
      Configs::Discord.stub(:client_secret, "secret") do
        Faraday.stub(:post, ->(*) { raise faraday_error }) do
          error = assert_raises(DiscordClient::ApiError) do
            DiscordClient.exchange_code("bad-code", redirect_uri: "https://example.com/callback")
          end

          assert_includes error.message, "connection refused"
        end
      end
    end
  end

  test "Faraday 요청에 timeout을 설정한다" do
    timeout_values = []
    response = Struct.new(:success?, :status, :body).new(true, 200, { "guild" => { "id" => "G1" } }.to_json)

    request_factory = lambda do
      options = Struct.new(:open_timeout, :timeout).new
      Struct.new(:headers, :body, :options).new({}, nil, options)
    end

    Configs::Discord.stub(:client_id, "dc-123") do
      Configs::Discord.stub(:client_secret, "secret") do
        Faraday.stub(:post, lambda { |url, &block|
          req = request_factory.call
          block.call(req)
          timeout_values << [ url, req.options.open_timeout, req.options.timeout ]
          response
        }) do
          DiscordClient.exchange_code("good-code", redirect_uri: "https://example.com/callback")
        end
      end
    end

    assert_equal [
      [ DiscordClient::TOKEN_URL, 5, 10 ]
    ], timeout_values
  end
  test "OAuth verification accepts the actual webhook target and applies timeouts" do
    Configs::Discord.stub(:client_id, "12345") do
      Faraday.stub(:get, lambda { |url, &block|
        assert_equal "https://discord.com/api/v10/webhooks/123/token", url
        request = Struct.new(:options).new(Struct.new(:open_timeout, :timeout).new)
        block.call(request)

        assert_equal 5, request.options.open_timeout
        assert_equal 10, request.options.timeout
        webhook_response(verified_webhook)
      }) { DiscordClient.verify_oauth_target!(approved_oauth) }
    end
  end

  test "OAuth verification rejects mismatched guild channel application and webhook identity" do
    { "guild_id" => "other", "channel_id" => "other", "application_id" => "other", "id" => "other", "type" => 2 }.each do |key, value|
      response = webhook_response(verified_webhook.merge(key => value))
      Configs::Discord.stub(:client_id, "12345") do
        with_webhook_response(response) do
          assert_raises(DiscordClient::ApiError) { DiscordClient.verify_oauth_target!(approved_oauth) }
        end
      end
    end
  end

  test "OAuth verification rejects unsafe URLs without sending any requests" do
    [ "http://discord.com/api/webhooks/123/token", "https://discord.com.attacker.test/api/webhooks/123/token",
      "https://discord.com/api/webhooks/123/token?wait=true", "https://user@discord.com/api/webhooks/123/token" ].each do |url|
      oauth = approved_oauth
      oauth[:webhook][:url] = url

      Faraday.stub(:get, ->(*) { flunk "Invalid webhook must not trigger a request" }) do
        assert_raises(DiscordClient::ApiError) { DiscordClient.verify_oauth_target!(oauth) }
      end
    end
  end

  test "OAuth verification rejects disagreement between the approved guild and webhook guild" do
    oauth = approved_oauth
    oauth[:webhook][:guild_id] = "other"

    Faraday.stub(:get, ->(*) { flunk "Mismatched guild must not trigger a request" }) do
      assert_raises(DiscordClient::ApiError) { DiscordClient.verify_oauth_target!(oauth) }
    end
  end

  test "OAuth verification rejects unsuccessful or malformed provider responses" do
    responses = [ Struct.new(:success?, :status, :body).new(false, 404, ""),
                  Struct.new(:success?, :status, :body).new(true, 200, "not JSON"), webhook_response([]) ]
    responses.each do |response|
      with_webhook_response(response) do
        assert_raises(DiscordClient::ApiError) { DiscordClient.verify_oauth_target!(approved_oauth) }
      end
    end
  end

  test "OAuth verification refuses to trust a webhook when client_id is not configured" do
    response = webhook_response(verified_webhook.except("application_id"))

    Configs::Discord.stub(:client_id, nil) do
      with_webhook_response(response) do
        error = assert_raises(DiscordClient::ApiError) { DiscordClient.verify_oauth_target!(approved_oauth) }

        assert_includes error.message, "client_id"
      end
    end
  end

  test "OAuth verification compares application_id as a string" do
    Configs::Discord.stub(:client_id, 12345) do
      with_webhook_response(webhook_response(verified_webhook)) do
        assert_nil DiscordClient.verify_oauth_target!(approved_oauth)
      end
    end
  end

  test "OAuth verification names the mismatched fields" do
    response = webhook_response(verified_webhook.merge("channel_id" => "other", "type" => 2))

    Configs::Discord.stub(:client_id, "12345") do
      with_webhook_response(response) do
        error = assert_raises(DiscordClient::ApiError) { DiscordClient.verify_oauth_target!(approved_oauth) }

        assert_includes error.message, "channel_id"
        assert_includes error.message, "type"
        refute_includes error.message, "guild_id"
      end
    end
  end

  test "OAuth verification reports the HTTP status of a failed lookup" do
    Configs::Discord.stub(:client_id, "12345") do
      with_webhook_response(Struct.new(:success?, :status, :body).new(false, 429, "")) do
        error = assert_raises(DiscordClient::ApiError) { DiscordClient.verify_oauth_target!(approved_oauth) }

        assert_includes error.message, "429"
      end
    end
  end

  test "OAuth verification wraps network errors without leaking the webhook token" do
    Configs::Discord.stub(:client_id, "12345") do
      Faraday.stub(:get, ->(*) { raise Faraday::ConnectionFailed, "Failed to open https://discord.com/api/v10/webhooks/123/token" }) do
        error = assert_raises(DiscordClient::ApiError) { DiscordClient.verify_oauth_target!(approved_oauth) }

        assert_includes error.message, "Faraday::ConnectionFailed"
        refute_includes error.message, "/123/token"
      end
    end
  end

  test "provider_webhook_url? accepts only Discord webhook URLs" do
    assert DiscordClient.provider_webhook_url?("https://discord.com/api/webhooks/123/token")
    assert DiscordClient.provider_webhook_url?("https://discord.com/api/v10/webhooks/123/token")
    assert_not DiscordClient.provider_webhook_url?("https://discord.com.attacker.test/api/webhooks/123/token")
    assert_not DiscordClient.provider_webhook_url?("https://discord.com/api/webhooks/123/token?wait=true")
    assert_not DiscordClient.provider_webhook_url?(nil)
  end

  test "exchange_code rejects JSON responses without an OAuth object" do
    response = Struct.new(:success?, :status, :body).new(true, 200, "[]")

    Faraday.stub(:post, ->(*) { response }) do
      assert_raises(DiscordClient::ApiError) do
        DiscordClient.exchange_code("code", redirect_uri: "https://example.com/callback")
      end
    end
  end

  private

  def approved_oauth
    { guild: { id: "G123" }, webhook: { guild_id: "G123", channel_id: "C123", url: "https://discord.com/api/webhooks/123/token" } }.with_indifferent_access
  end

  def verified_webhook
    { "id" => "123", "type" => 1, "guild_id" => "G123", "channel_id" => "C123", "application_id" => "12345" }
  end

  def webhook_response(body)
    Struct.new(:success?, :status, :body).new(true, 200, body.to_json)
  end

  def with_webhook_response(response)
    Faraday.stub(:get, ->(_url, &block) {
      request = Struct.new(:options).new(Struct.new(:open_timeout, :timeout).new)
      block.call(request)
      response
    }) { yield }
  end
end
