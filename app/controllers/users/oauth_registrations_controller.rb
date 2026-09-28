# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

class Users::OauthRegistrationsController < ApplicationController
  skip_before_action :authenticate_user!

  layout -> { Components::Layout }

  def new
    oauth_signup = session[:oauth_signup]
    return redirect_to(new_user_session_path, alert: t("users.oauth_signup.session_missing")) unless oauth_signup

    @user = User.new(username: OauthAccounts::Callbacks.suggest_username(name: oauth_signup["name"], email: oauth_signup["email"]))
    render Views::Users::OauthSignup.new(user: @user, email: oauth_signup["email"], name: oauth_signup["name"])
  end

  # 세션의 가입 payload로 등록하고 성공 시 가입 상태를 정리한다.
  def create
    oauth_signup = session[:oauth_signup]
    return redirect_to(new_user_session_path, alert: t("users.oauth_signup.session_missing")) unless oauth_signup

    result = OauthAccounts::Registration.register_user(
      signup_payload: oauth_signup,
      username: oauth_registration_params[:username],
      locale: safe_locale,
      signup_host: safe_signup_host
    )

    if result.success?
      session.delete(:oauth_signup)
      if result.user.active_for_authentication?
        sign_in(:user, result.user)
        redirect_to root_path, notice: t("devise.omniauth_callbacks.success", kind: oauth_signup["provider"].to_s.humanize)
      else
        redirect_to new_user_session_path, notice: t("devise.registrations.signed_up_but_unconfirmed")
      end
    else
      @user = result.user
      render Views::Users::OauthSignup.new(user: @user, email: oauth_signup["email"], name: oauth_signup["name"]), status: :unprocessable_entity
    end
  end

  private

  def oauth_registration_params
    params.expect(user: [ :username ])
  end

  def safe_locale
    locale = I18n.locale.to_s
    User::SUPPORTED_LOCALES.include?(locale) ? locale : User::SUPPORTED_LOCALES.first
  end

  def safe_signup_host
    host = request.host.to_s.downcase
    User::SUPPORTED_SIGNUP_HOSTS.include?(host) ? host : User::SUPPORTED_SIGNUP_HOSTS.first
  end
end
