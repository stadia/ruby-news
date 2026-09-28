# frozen_string_literal: true

require "test_helper"

class MastodonClientTest < ActiveSupport::TestCase
  test "명시한 설정의 토큰으로 HTTP 요청을 인증한다" do
    config = Data.define(:site, :access_token).new("https://social.example", "test-access-token")
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/api/v1/statuses") do |env|
        assert_equal "Bearer test-access-token", env.request_headers["Authorization"]
        [ 200, { "Content-Type" => "application/json" }, "{}" ]
      end
      stub.delete("/api/v1/statuses/test-id") do |env|
        assert_equal "Bearer test-access-token", env.request_headers["Authorization"]
        [ 200, { "Content-Type" => "application/json" }, "{}" ]
      end
    end

    Preference.stub(:get_object, ->(*) { flunk "클라이언트는 Preference를 조회하지 않아야 합니다" }) do
      client = MastodonClient.new(oauth_config: config)
      client.client.adapter(:test, stubs)

      assert_equal 200, client.post("테스트").status
      assert_equal 200, client.delete("test-id").status
    end

    stubs.verify_stubbed_calls
  end

  test "설정이 없으면 생성할 수 없다" do
    assert_raises(ArgumentError) { MastodonClient.new }
    error = assert_raises(ArgumentError) { MastodonClient.new(oauth_config: nil) }
    assert_match(/OAuth/, error.message)
  end

  test "액세스 토큰이 비어 있으면 생성할 수 없다" do
    [ nil, "", " " ].each do |access_token|
      config = Data.define(:site, :access_token).new("https://social.example", access_token)
      error = assert_raises(ArgumentError) { MastodonClient.new(oauth_config: config) }
      assert_match(/토큰/, error.message)
    end
  end

  test "인스턴스 주소가 비어 있으면 생성할 수 없다" do
    [ nil, "", " " ].each do |site|
      config = Data.define(:site, :access_token).new(site, "test-access-token")
      error = assert_raises(ArgumentError) { MastodonClient.new(oauth_config: config) }

      assert_match(/주소/, error.message)
    end
  end
end
