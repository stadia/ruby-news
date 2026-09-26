# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

# Slack·Discord OAuth 콜백이 실패로 끝나는 공통 경로다.
# 사용자에게는 번역된 안내만 보여 주고, 원인은 운영 진단을 위해 로그에 남긴다.
# 로그에는 공급자 오류 코드와 식별자만 담고 토큰·webhook URL은 담지 않는다.
module OauthCallbackFailures
  extend ActiveSupport::Concern

  private

  # 공급자가 오류를 돌려줬거나 code 없이 돌아온 콜백이면 결과 화면으로 보내고 true를 돌려준다.
  # 사용자 취소(access_denied)는 정상 흐름이라 info로, 나머지는 설정 오류일 수 있어 warn으로 남긴다.
  #: (String provider) -> bool
  def redirect_provider_error?(provider)
    error = params[:error].to_s
    return false if error.empty? && params[:code].present?

    cancelled = error == "access_denied"
    message = "#{provider} OAuth provider error error=#{error.truncate(100).inspect} " \
              "description=#{params[:error_description].to_s.truncate(200).inspect} code_present=#{params[:code].present?}"
    cancelled ? logger.info(message) : logger.warn(message)

    key = cancelled ? "oauth.errors.cancelled" : "oauth.errors.provider_failure"
    redirect_to oauth_result_path(provider:, success: "false", error: t(key))
    true
  end

  #: (String provider, NotificationChannel::RelinkRejected error) -> void
  def redirect_relink_rejected(provider, error)
    logger.warn("#{provider} OAuth #{error.message}")
    redirect_to oauth_result_path(provider:, success: "false", error: t("oauth.errors.relink_not_allowed"))
  end

  # 공급자 API 실패는 일시 장애나 설정 오류이고, DB 오류는 서버 결함이라 로그 수준을 나눈다.
  #: (String provider, StandardError error) -> void
  def redirect_callback_failure(provider, error)
    message = "#{provider} OAuth callback failed: #{error.class}: #{error.message}"
    error.is_a?(ActiveRecord::ActiveRecordError) ? logger.error(message) : logger.warn(message)
    redirect_to oauth_result_path(provider:, success: "false", error: t("oauth.errors.provider_failure"))
  end
end
