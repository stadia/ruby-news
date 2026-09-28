# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

module OauthAccounts
  module Callbacks
    extend FunctionLogger

    MIN_LENGTH = 2
    MAX_LENGTH = 30

    # 콜백 처리 결과를 표현하는 불변 sum type.
    # 기존 user와 매칭되면 SignIn, 신규면 CompleteSignup을 반환한다.
    # HTTP 세션은 다루지 않는다. 결과의 저장·정리는 호출자 책임이다.
    # 멤버 타입: sorbet/rbi/shims/data_definitions.rbi
    SignIn = Data.define(:user)
    CompleteSignup = Data.define(:signup_payload)

    SIGNUP_PAYLOAD_KEYS = %i[provider uid email email_verified relay_email name raw_info].freeze

    class << self
      # 인증 정보를 정규화해 로그인 사용자 또는 가입에 필요한 payload를 반환한다.
      #: (auth: untyped) -> (SignIn | CompleteSignup)
      def handle_callback(auth:)
        oauth_data = build_auth_result(auth:)
        user = match_user(
          provider: oauth_data[:provider],
          uid: oauth_data[:uid],
          email: oauth_data[:email],
          email_verified: oauth_data[:email_verified],
          relay_email: oauth_data[:relay_email]
        )

        if user
          upsert_oauth_account(user:, oauth_data:)

          return SignIn.new(user:)
        end

        CompleteSignup.new(
          signup_payload: oauth_data.slice(*SIGNUP_PAYLOAD_KEYS).deep_stringify_keys
        )
      end

      # 가입 화면에서 사용할 중복 없는 username을 이름 또는 이메일로 제안한다.
      def suggest_username(name:, email:)
        base = sanitize(name).presence || sanitize(email.to_s.split("@").first).presence || "user"
        base = "user#{base}" if base.length < MIN_LENGTH
        base = base.first(MAX_LENGTH)

        unique_username_for(base)
      end

      private

      def upsert_oauth_account(user:, oauth_data:)
        oauth_account = OauthAccount.find_or_initialize_by(provider: oauth_data[:provider], uid: oauth_data[:uid])
        oauth_account.user = user
        if oauth_data[:email].present?
          oauth_account.email = oauth_data[:email]
          oauth_account.email_verified = oauth_data[:email_verified]
        end
        oauth_account.raw_info = merged_raw_info(existing: oauth_account.raw_info, incoming: oauth_data[:raw_info])
        oauth_account.save!
        oauth_account
      rescue ActiveRecord::RecordNotUnique
        OauthAccount.find_by!(provider: oauth_data[:provider], uid: oauth_data[:uid])
      end

      def match_user(provider:, uid:, email:, email_verified:, relay_email:)
        oauth_account = OauthAccount.find_by(provider:, uid: uid.to_s)
        return oauth_account.user if oauth_account
        return unless email_verified
        return if relay_email
        return if email.blank?

        User.find_by(email: email.to_s.strip.downcase)
      end

      def build_auth_result(auth:)
        info = auth.fetch("info", {}).with_indifferent_access
        credentials = auth.fetch("credentials", {}).with_indifferent_access
        provider = auth.fetch("provider")
        email = info[:email].to_s.presence
        github_email = GithubEmails.primary_verified_email(credentials[:token]) if provider.to_s == "github" && email.blank?
        email ||= github_email

        {
          provider:,
          uid: auth.fetch("uid").to_s,
          email:,
          email_verified: verified_email?(provider:, info:, credentials:, email:, github_email:),
          relay_email: relay_email?(email),
          name: info[:name].to_s.presence,
          raw_info: {
            "provider" => provider,
            "uid" => auth.fetch("uid").to_s,
            "info" => info.slice(:email, :name, :email_verified).to_h
          }
        }
      end

      def sanitize(value)
        value.to_s.downcase
             .gsub(/\s+/, "_")
             .gsub(/[^a-z0-9_.]/, "")
             .gsub(/_{2,}/, "_")
             .gsub(/\A[._]+|[._]+\z/, "")
      end

      MAX_USERNAME_RETRIES = 10

      def unique_username_for(base)
        return base unless User.exists?(username: base)

        MAX_USERNAME_RETRIES.times do |i|
          suffix = (i + 1).to_s
          candidate = "#{base.first(MAX_LENGTH - suffix.length - 1)}_#{suffix}"
          return candidate unless User.exists?(username: candidate)
        end

        "#{base.first(MAX_LENGTH - 6)}_#{SecureRandom.hex(2)}"
      end

      def relay_email?(email)
        email.to_s.downcase.ends_with?("@privaterelay.appleid.com")
      end

      def verified_email?(provider:, info:, credentials:, email: nil, github_email: nil)
        value = case provider.to_s
        when "google_oauth2"
          info[:email_verified]
        when "apple"
          info[:email_verified].nil? ? credentials[:email_verified] : info[:email_verified]
        when "github"
          email.present?
        else
          info[:email_verified] || credentials[:email_verified]
        end

        ActiveModel::Type::Boolean.new.cast(value)
      end

      def merged_raw_info(existing:, incoming:)
        existing_info = existing.to_h.deep_stringify_keys
        incoming_info = incoming.to_h.deep_stringify_keys

        existing_info.deep_merge(incoming_info) do |_key, old_value, new_value|
          case new_value
          when nil
            old_value
          when String, Array, Hash
            new_value.empty? ? old_value : new_value
          else
            new_value
          end
        end
      end
    end
  end
end
