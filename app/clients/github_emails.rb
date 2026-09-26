# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

# GitHub REST API `/user/emails` 조회(Infrastructure).
# OAuth payload에 email이 없을 때 OauthAccounts::Callbacks가 사용한다.
module GithubEmails
  URL = "https://api.github.com/user/emails"
  OPEN_TIMEOUT = 2 #: Integer
  REQUEST_TIMEOUT = 5 #: Integer

  class << self
    # primary이면서 verified인 email. 없거나 조회에 실패하면 nil이다.
    #: (String? token) -> String?
    def primary_verified_email(token)
      return if token.blank?

      response = Faraday.get(URL, nil, headers(token)) do |req|
        req.options.timeout = REQUEST_TIMEOUT
        req.options.open_timeout = OPEN_TIMEOUT
      end
      return unless response.status == 200

      emails = JSON.parse(response.body)
      return unless emails.is_a?(Array)

      primary = emails.find { |entry| entry["primary"] && entry["verified"] }

      primary&.fetch("email", nil).to_s.presence
    rescue Faraday::Error, JSON::ParserError
      nil
    end

    private

    #: (String token) -> Hash[String, String]
    def headers(token)
      {
        "Authorization" => "Bearer #{token}",
        "Accept" => "application/vnd.github+json",
        "X-GitHub-Api-Version" => "2022-11-28"
      }
    end
  end
end
