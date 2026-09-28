# frozen_string_literal: true

require "test_helper"

class MastodonClientTest < ActiveSupport::TestCase
  test "명시한 문자열 토큰으로 HTTP 요청을 인증한다" do
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
      client = MastodonClient.new(site: "https://social.example", access_token: "test-access-token")
      client.client.adapter(:test, stubs)

      assert_equal 200, client.post("테스트").status
      assert_equal 200, client.delete("test-id").status
    end

    stubs.verify_stubbed_calls
  end

  test "필수 키워드를 생략하면 생성할 수 없다" do
    assert_raises(ArgumentError) { MastodonClient.new }
  end

  test "액세스 토큰이 비어 있으면 생성할 수 없다" do
    [ nil, "", " " ].each do |access_token|
      error = assert_raises(ArgumentError) { MastodonClient.new(site: "https://social.example", access_token:) }
      assert_match(/토큰/, error.message)
    end
  end

  test "인스턴스 주소가 비어 있으면 생성할 수 없다" do
    [ nil, "", " " ].each do |site|
      error = assert_raises(ArgumentError) { MastodonClient.new(site:, access_token: "test-access-token") }

      assert_match(/주소/, error.message)
    end
  end
  test "게시와 삭제 로그에 Bearer 토큰과 본문을 남기지 않는다" do
    secret = "sensitive-access-token"
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/api/v1/statuses") { [ 200, { "Content-Type" => "application/json" }, { token: secret }.to_json ] }
      stub.delete("/api/v1/statuses/test-id") { [ 200, { "Content-Type" => "application/json" }, { token: secret }.to_json ] }
    end
    output, = capture_io do
      client = MastodonClient.new(site: "https://social.example", access_token: secret)
      client.client.adapter(:test, stubs)
      client.post("sensitive-post-body")
      client.delete("test-id")
    end

    assert_includes output, "/api/v1/statuses"
    refute_includes output, secret
    refute_includes output, "sensitive-post-body"
    refute_includes output, "Bearer"
    stubs.verify_stubbed_calls
  end
end
