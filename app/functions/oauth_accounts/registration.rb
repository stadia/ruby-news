# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

module OauthAccounts
  module Registration
    extend FunctionLogger

    # 등록 결과를 담는 불변 값 객체.
    # 멤버 타입: sorbet/rbi/shims/data_definitions.rbi
    Result = Data.define(:success, :user)

    class Result
      #: () -> bool
      def success? = success
    end

    class << self
      #: (signup_payload: untyped, username: String, locale: String, signup_host: String) -> Result
      def register_user(signup_payload:, username:, locale:, signup_host:)
        payload = signup_payload.with_indifferent_access
        user = build_user(payload:, username:, locale:, signup_host:)

        User.transaction do
          user.save!
          OauthAccount.create!(
            user: user,
            provider: payload.fetch(:provider),
            uid: payload.fetch(:uid),
            email: payload[:email],
            email_verified: payload[:email_verified],
            raw_info: payload[:raw_info] || {}
          )
        end

        Result.new(success: true, user:)
      rescue ActiveRecord::RecordInvalid => e
        unless e.record.is_a?(User)
          user.errors.add(:base, e.record.errors.full_messages.to_sentence)
        end
        Result.new(success: false, user:)
      rescue ActiveRecord::RecordNotUnique
        user.errors.add(:base, I18n.t("users.oauth_signup.duplicate_account", default: "이미 연결된 OAuth 계정입니다."))
        Result.new(success: false, user:)
      end

      private

      def build_user(payload:, username:, locale:, signup_host:)
        User.new(
          email: payload[:email],
          name: payload[:name].presence || username,
          username: username,
          locale: locale,
          signup_host: signup_host,
          password: Devise.friendly_token.first(32),
          password_confirmation: nil,
          confirmed_at: payload[:email_verified] ? Time.current : nil
        )
      end
    end
  end
end
