# frozen_string_literal: true

require "test_helper"

class OauthAccounts::CallbacksTest < ActiveSupport::TestCase
  # --- handle_callback ---

  test "google payload를 정규화한다" do
    result = OauthAccounts::Callbacks.send(:build_auth_result, auth: google_auth_hash(email: "john@example.com"))

    assert_equal "google_oauth2", result[:provider]
    assert_equal "google-123", result[:uid]
    assert_equal "john@example.com", result[:email]
    assert_equal "John Doe", result[:name]
    assert result[:email_verified]
    refute result[:relay_email]
  end

  test "apple relay email을 판별한다" do
    auth = {
      "provider" => "apple",
      "uid" => "apple-123",
      "info" => {
        "email" => "abc@privaterelay.appleid.com",
        "name" => "John Appleseed"
      },
      "credentials" => {
        "email_verified" => true
      }
    }

    result = OauthAccounts::Callbacks.send(:build_auth_result, auth: auth)

    assert result[:email_verified]
    assert result[:relay_email]
  end

  test "github payload에 email이 있으면 API를 호출하지 않는다" do
    GithubEmails.stub(:primary_verified_email, ->(*) { flunk "email이 있으면 조회하면 안 된다" }) do
      result = OauthAccounts::Callbacks.send(:build_auth_result, auth: github_auth_hash(email: "octo@example.com"))

      assert_equal "octo@example.com", result[:email]
    end
  end

  test "github 아닌 provider는 email이 없어도 API를 호출하지 않는다" do
    GithubEmails.stub(:primary_verified_email, ->(*) { flunk "다른 provider는 조회하면 안 된다" }) do
      [ google_auth_hash(email: nil), apple_auth_hash(email: nil, name: nil) ].each do |auth|
        result = OauthAccounts::Callbacks.send(:build_auth_result, auth:)

        assert_nil result[:email]
      end
    end
  end

  test "github payload를 정규화한다" do
    result = OauthAccounts::Callbacks.send(:build_auth_result, auth: github_auth_hash(email: "octo@example.com"))

    assert_equal "github", result[:provider]
    assert_equal "github-123", result[:uid]
    assert_equal "octo@example.com", result[:email]
    assert_equal "Octo Cat", result[:name]
    assert result[:email_verified]
    refute result[:relay_email]
  end

  test "github payload에 email이 없으면 primary verified email을 조회한다" do
    GithubEmails.stub(:primary_verified_email, ->(token) { token == "github-token" ? "octo@example.com" : flunk("unexpected token: #{token}") }) do
      result = OauthAccounts::Callbacks.send(:build_auth_result, auth: github_auth_hash(email: nil))

      assert_equal "octo@example.com", result[:email]
      assert result[:email_verified]
    end
  end

  test "github verified primary email을 찾지 못하면 email_verified는 false다" do
    requested_token = nil
    lookup = ->(token) { requested_token = token; nil }
    GithubEmails.stub(:primary_verified_email, lookup) do
      result = OauthAccounts::Callbacks.send(:build_auth_result, auth: github_auth_hash(email: nil))

      assert_nil result[:email]
      refute result[:email_verified]
    end
    assert_equal "github-token", requested_token
  end

  test "existing oauth account면 sign_in 결과를 반환한다" do
    user = users(:john)
    OauthAccount.create!(user:, provider: "google_oauth2", uid: "google-123")

    result = OauthAccounts::Callbacks.handle_callback(auth: google_auth_hash(email: user.email))

    assert_instance_of OauthAccounts::Callbacks::SignIn, result
    assert_equal user, result.user
  end

  test "verified email 기존 user를 oauth account에 연결한다" do
    user = users(:john)

    result = OauthAccounts::Callbacks.handle_callback(auth: google_auth_hash(email: user.email))

    assert_instance_of OauthAccounts::Callbacks::SignIn, result
    assert_equal user, result.user
    account = OauthAccount.find_by(provider: "google_oauth2", uid: "google-123")

    assert_equal user, account.user
  end

  test "기존 oauth account 로그인 시 빈 provider 정보로 기존 값을 덮어쓰지 않는다" do
    user = users(:john)
    OauthAccount.create!(
      user:,
      provider: "apple",
      uid: "apple-123",
      email: "first-login@example.com",
      email_verified: true,
      raw_info: {
        "provider" => "apple",
        "uid" => "apple-123",
        "info" => {
          "email" => "first-login@example.com",
          "name" => "First Login"
        }
      }
    )

    result = OauthAccounts::Callbacks.handle_callback(auth: apple_auth_hash(email: nil, name: nil))

    assert_instance_of OauthAccounts::Callbacks::SignIn, result

    account = OauthAccount.find_by!(provider: "apple", uid: "apple-123")

    assert_equal "first-login@example.com", account.email
    assert_equal "First Login", account.raw_info.dig("info", "name")
    assert account.email_verified, "Apple 후속 콜백에서 email_verified가 덮어써지면 안 됨"
  end

  test "기존 oauth account 로그인 시 false 값도 raw_info에 반영한다" do
    user = users(:john)
    OauthAccount.create!(
      user:,
      provider: "google_oauth2",
      uid: "google-123",
      email: user.email,
      email_verified: true,
      raw_info: {
        "provider" => "google_oauth2",
        "uid" => "google-123",
        "info" => {
          "email" => user.email,
          "name" => "First Login",
          "email_verified" => true
        }
      }
    )

    auth = google_auth_hash(email: user.email)
    auth["info"]["email_verified"] = false

    result = OauthAccounts::Callbacks.handle_callback(auth:)

    assert_instance_of OauthAccounts::Callbacks::SignIn, result
    refute OauthAccount.find_by!(provider: "google_oauth2", uid: "google-123").raw_info.dig("info", "email_verified")
  end

  test "신규 user면 username 중복 조회 없이 signup completion 결과를 반환한다" do
    username_queries = []
    subscriber = lambda do |event|
      sql = event.payload[:sql]
      username_queries << sql if sql.match?(/SELECT .*"users"\."username"/m)
    end

    result = ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      OauthAccounts::Callbacks.handle_callback(auth: google_auth_hash(email: "new-user@example.com", name: "New User"))
    end

    assert_instance_of OauthAccounts::Callbacks::CompleteSignup, result
    assert_empty username_queries
    assert_equal "new-user@example.com", result.signup_payload["email"]
  end

  test "signup completion 결과의 signup payload는 가입 완료에 필요한 값만 문자열 키로 담는다" do
    result = OauthAccounts::Callbacks.handle_callback(auth: google_auth_hash(email: "new-user@example.com", name: "New User"))

    assert_equal %w[provider uid email email_verified relay_email name raw_info].sort, result.signup_payload.keys.sort
    assert_equal "google_oauth2", result.signup_payload["provider"]
    assert_equal "google-123", result.signup_payload["uid"]
    assert result.signup_payload["email_verified"]
    refute result.signup_payload["relay_email"]
    assert_equal "New User", result.signup_payload["name"]
  end

  test "signup completion 결과의 signup payload에 raw_info를 보존한다" do
    result = OauthAccounts::Callbacks.handle_callback(
      auth: apple_auth_hash(email: "first-login@example.com", name: "First Login")
    )

    assert_equal "first-login@example.com", result.signup_payload.dig("raw_info", "info", "email")
    assert_equal "First Login", result.signup_payload.dig("raw_info", "info", "name")
  end

  # --- match_user (private) ---

  test "existing oauth account가 있으면 해당 사용자를 반환한다" do
    user = users(:john)
    OauthAccount.create!(user:, provider: "google_oauth2", uid: "google-123")

    assert_equal user, OauthAccounts::Callbacks.send(:match_user, provider: "google_oauth2", uid: "google-123", email: "other@example.com", email_verified: true, relay_email: false)
  end

  test "verified email이면 기존 user를 자동 연결한다" do
    user = users(:john)

    assert_equal user, OauthAccounts::Callbacks.send(:match_user, provider: "google_oauth2", uid: "google-123", email: user.email, email_verified: true, relay_email: false)
  end

  test "verified email이 아니면 기존 user를 자동 연결하지 않는다" do
    assert_nil OauthAccounts::Callbacks.send(:match_user, provider: "google_oauth2", uid: "google-123", email: users(:john).email, email_verified: false, relay_email: false)
  end

  test "apple relay email이면 기존 user를 자동 연결하지 않는다" do
    assert_nil OauthAccounts::Callbacks.send(:match_user, provider: "apple", uid: "apple-123", email: users(:john).email, email_verified: true, relay_email: true)
  end

  # --- suggest_username (public) ---

  test "name 기반 username을 제안한다" do
    assert_equal "john_doe", OauthAccounts::Callbacks.suggest_username(name: "John Doe", email: "john@example.com")
  end

  test "허용 문자만 남긴다" do
    assert_equal "johndoe", OauthAccounts::Callbacks.send(:sanitize, 'John!@#$Doe')
  end

  test "중복이면 suffix를 붙인다" do
    User.create!(email: "john-doe@example.com", username: "john_doe", name: "John Doe", password: "password123", confirmed_at: Time.current)

    assert_equal "john_doe_1", OauthAccounts::Callbacks.suggest_username(name: "John Doe", email: "other@example.com")
  end

  test "너무 짧으면 fallback을 보정한다" do
    assert_equal "user", OauthAccounts::Callbacks.suggest_username(name: "!", email: nil)
  end

  private

  def google_auth_hash(email:, name: "John Doe")
    {
      "provider" => "google_oauth2",
      "uid" => "google-123",
      "info" => {
        "email" => email,
        "name" => name,
        "email_verified" => true
      }
    }
  end

  def apple_auth_hash(email:, name:)
    {
      "provider" => "apple",
      "uid" => "apple-123",
      "info" => {
        "email" => email,
        "name" => name
      },
      "credentials" => {
        "email_verified" => true
      }
    }
  end

  def github_auth_hash(email:, name: "Octo Cat")
    {
      "provider" => "github",
      "uid" => "github-123",
      "info" => {
        "email" => email,
        "name" => name
      },
      "credentials" => {
        "token" => "github-token"
      }
    }
  end
end
