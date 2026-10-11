# frozen_string_literal: true

require "test_helper"

class SocialControllerTest < ActionDispatch::IntegrationTest
  def setup
    @admin = users(:admin)
    sign_in_as(@admin)
  end

  test "GET provider_callback redirects with alert when state mismatches" do
    get "/social/xcom/callback?code=auth_code&state=wrong_state"

    assert_redirected_to madmin_social_index_path
  end

  # OAuth Preference 미설정 시 OauthClient.build의 ArgumentError가 500이 아니라 안내 redirect가 되어야 한다.
  test "GET provider_authorize redirects with alert when oauth config is missing" do
    get "/social/xcom/authorize"

    assert_redirected_to madmin_social_index_path
    assert_match "OAuth 설정이 비어있습니다", flash[:alert]
  end

  test "GET provider_callback redirects with alert when oauth config is missing" do
    get "/social/xcom/callback", params: { code: "auth_code", state: "state123" }

    assert_redirected_to madmin_social_index_path
    assert_match "OAuth 설정이 비어있습니다", flash[:alert]
  end

  # 콜백 성공 시 인가 시작 때 조회한 oauth preference에 토큰이 저장된다(재조회 없이 동일 객체 재사용).
  test "GET provider_callback saves token into the existing oauth preference" do
    pref = Preference.create!(name: "xcom_oauth", value: {
      "client_id" => "cid", "client_secret" => "secret", "site" => "https://api.x.com/2/"
    })

    token = Struct.new(:token, :refresh_token, :expires_at).new("access123", "refresh456", 2.hours.from_now.to_i)
    auth_code = Object.new
    auth_code.define_singleton_method(:authorize_url) { |**_kwargs| "https://x.com/i/oauth2/authorize?client_id=cid&state=state123" }
    auth_code.define_singleton_method(:get_token) { |*_args, **_kwargs| token }
    fake_client = Struct.new(:auth_code).new(auth_code)

    OauthClient.stub(:build, fake_client) do
      get "/social/xcom/authorize"

      assert_redirected_to "https://x.com/i/oauth2/authorize?client_id=cid&state=state123"

      get "/social/xcom/callback", params: { code: "auth_code", state: "state123" }

      assert_redirected_to madmin_social_index_path
    end

    pref.reload

    assert_equal "access123", pref.value["access_token"]
    assert_equal "refresh456", pref.value["refresh_token"]
  ensure
    pref&.destroy
  end

  # 사이트 소셜 게시 토큰은 관리자만 연결할 수 있다.
  test "non-admin cannot authorize or overwrite site oauth token" do
    pref = Preference.create!(name: "xcom_oauth", value: {
      "client_id" => "cid", "client_secret" => "secret", "site" => "https://api.x.com/2/", "access_token" => "site_token"
    })
    sign_in_as(users(:john))

    get "/social/xcom/authorize"

    assert_response :not_found

    get "/social/xcom/callback", params: { code: "auth_code", state: "state123" }

    assert_response :not_found
    assert_equal "site_token", pref.reload.value["access_token"]
  ensure
    pref&.destroy
  end
end
