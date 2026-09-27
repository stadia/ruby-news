# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  layout -> { Components::Layout }

  before_action :verify_google_config, only: :google_oauth2
  before_action :verify_apple_config, only: :apple
  before_action :verify_github_config, only: :github

  def google_oauth2
    handle_oauth_callback
  end

  def apple
    handle_oauth_callback
  end

  def github
    handle_oauth_callback
  end

  private

  def verify_google_config
    return if Configs::GoogleOauth.configured?

    redirect_to new_user_session_path, alert: t("users.omniauth_callbacks.not_configured", provider: "Google")
  end

  def verify_apple_config
    return if Configs::AppleOauth.configured?

    redirect_to new_user_session_path, alert: t("users.omniauth_callbacks.not_configured", provider: "Apple")
  end

  def verify_github_config
    return if Configs::GithubOauth.configured?

    redirect_to new_user_session_path, alert: t("users.omniauth_callbacks.not_configured", provider: "GitHub")
  end

  def handle_oauth_callback
    result = oauth_callback_result

    case result
    when OauthAccounts::Callbacks::SignIn
      session.delete(:oauth_signup)
      sign_in(resource_name, result.user)
      redirect_to root_path, notice: t("devise.omniauth_callbacks.success", kind: provider_name)
    when OauthAccounts::Callbacks::CompleteSignup
      session[:oauth_signup] = result.signup_payload
      redirect_to new_user_oauth_registration_path
    else
      # handle_callback의 sum type에 새 variant가 추가됐을 때 render 없이
      # fall-through해 MissingExactTemplate 500로 죽는 대신 loudly 실패한다.
      raise ArgumentError, "unexpected callback result: #{result.class}"
    end
  rescue KeyError, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
    logger.warn("[OAuth callback failure] provider=#{provider_name} error=#{e.class}: #{e.message}")
    redirect_to new_user_session_path, alert: t("devise.omniauth_callbacks.failure", kind: provider_name, reason: "OAuth 인증 처리 실패")
  end

  #: () -> untyped
  def oauth_callback_result
    OauthAccounts::Callbacks.handle_callback(auth: request.env["omniauth.auth"])
  end

  def provider_name
    request.env.dig("omniauth.auth", "provider").to_s.humanize.presence || "OAuth"
  end
end
