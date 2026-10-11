# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

class SocialController < ApplicationController
  before_action :require_admin
  before_action :set_oauth_client, only: %i[provider_authorize provider_callback]

  # provider OAuth2 인증 시작
  #: () -> void
  def provider_authorize
    # PKCE 사용 (X.com OAuth2.0 요구사항)
    code_verifier = SecureRandom.urlsafe_base64(32)

    session["#{provider}_code_verifier"] = code_verifier

    authorize_url = authorize_url(@client, code_verifier)

    session["#{provider}_state"] = authorize_url.match(/state=([^&]+)/)[1]

    redirect_to authorize_url, allow_other_host: true
  end

  # provider OAuth2 콜백 처리
  #: () -> void
  def provider_callback
    # State 검증
    if params[:state] != session["#{provider}_state"]
      redirect_to madmin_social_index_path, alert: "OAuth state 불일치 에러"
      return
    end

    begin
      token = @client.auth_code.get_token(
        params[:code],
        redirect_uri: social_provider_callback_url(provider: provider),
        code_verifier: session["#{provider}_code_verifier"]
      )

      # Access token을 기존 oauth preference에 저장한다.
      # set_oauth_client에서 설정 존재가 보장된 같은 객체를 재사용하므로 재조회하지 않는다.
      # Preference의 동적 setter가 키를 문자열로 정규화한다(TwitterService 토큰 갱신과 같은 경로).
      @oauth_config.update!(
        access_token: token.token,
        refresh_token: token.refresh_token,
        expires_at: token.expires_at,
        token_created_at: Time.current.to_i
      )

      session.delete("#{provider}_code_verifier")
      session.delete("#{provider}_state")

      redirect_to madmin_social_index_path, notice: t("social.oauth.success")
    rescue OAuth2::Error => e
      redirect_to madmin_social_index_path, alert: t("social.oauth.error", message: e.message)
    end
  end

  private

  # 사이트 소셜 게시 토큰을 저장하므로 관리자 전용이다.
  #: () -> void
  def require_admin
    head :not_found unless current_user&.admin?
  end

  # OAuth 설정이 없거나 잘못됐으면 500 대신 안내와 함께 redirect한다.
  # (OauthClient.build은 미설정/이름 누락/미지원 provider를 ArgumentError로 던진다)
  #: () -> void
  def set_oauth_client
    @oauth_config = Preference.get_object("#{provider}_oauth")
    @client = OauthClient.build(@oauth_config)
  rescue ArgumentError => e
    logger.warn "OAuth 설정 오류 (#{provider}): #{e.message}"
    redirect_to madmin_social_index_path, alert: t("social.oauth.error", message: e.message)
  end

  def provider
    params[:provider].presence || "xcom"
  end

  def authorize_url(client, code_verifier)
    scope = case provider
    when "xcom"
      "tweet.read tweet.write users.read offline.access"
    when "mastodon"
      "read:statuses write:statuses"
    end

    code_challenge = Base64.urlsafe_encode64(
      Digest::SHA256.digest(code_verifier),
      padding: false
    )

    client.auth_code.authorize_url(
      redirect_uri: social_provider_callback_url(provider: provider),
      scope: scope,
      code_challenge: code_challenge,
      code_challenge_method: "S256",
      state: SecureRandom.hex(16)
    )
  end
end
