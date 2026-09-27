# frozen_string_literal: true

require "test_helper"

class GithubEmailsTest < ActiveSupport::TestCase
  test "primary이면서 verified인 email을 반환한다" do
    body = [
      { email: "secondary@example.com", primary: false, verified: true },
      { email: "octo@example.com", primary: true, verified: true }
    ].to_json

    Faraday.stub(:get, github_get_response(status: 200, body:)) do
      assert_equal "octo@example.com", GithubEmails.primary_verified_email("token")
    end
  end

  test "토큰을 Bearer 헤더로 보내고 네트워크 timeout을 설정한다" do
    request_url = nil
    request_headers = nil
    request_options = nil
    github_get = lambda do |url, _params, headers, &block|
      request = Struct.new(:options).new(Struct.new(:timeout, :open_timeout).new)
      block.call(request)
      request_url = url
      request_headers = headers
      request_options = request.options
      Struct.new(:status, :body).new(200, [ { email: "octo@example.com", primary: true, verified: true } ].to_json)
    end

    Faraday.stub(:get, github_get) do
      GithubEmails.primary_verified_email("token")
    end

    assert_equal "https://api.github.com/user/emails", request_url
    assert_equal "Bearer token", request_headers["Authorization"]
    assert_equal 5, request_options.timeout
    assert_equal 2, request_options.open_timeout
  end

  test "토큰이 없으면 요청하지 않고 nil을 반환한다" do
    Faraday.stub(:get, ->(*) { flunk "요청하면 안 된다" }) do
      assert_nil GithubEmails.primary_verified_email(nil)
      assert_nil GithubEmails.primary_verified_email("")
    end
  end

  test "primary email이 verified가 아니면 nil을 반환한다" do
    body = [ { email: "octo@example.com", primary: true, verified: false } ].to_json

    Faraday.stub(:get, github_get_response(status: 200, body:)) do
      assert_nil GithubEmails.primary_verified_email("token")
    end
  end

  test "응답이 배열이 아니면 nil을 반환한다" do
    Faraday.stub(:get, github_get_response(status: 200, body: { message: "unexpected" }.to_json)) do
      assert_nil GithubEmails.primary_verified_email("token")
    end
  end

  test "200이 아니면 nil을 반환한다" do
    Faraday.stub(:get, github_get_response(status: 401, body: { message: "Bad credentials" }.to_json)) do
      assert_nil GithubEmails.primary_verified_email("token")
    end
  end

  test "네트워크 오류와 JSON 파싱 오류는 nil로 흡수한다" do
    Faraday.stub(:get, ->(*) { raise Faraday::ConnectionFailed, "down" }) do
      assert_nil GithubEmails.primary_verified_email("token")
    end

    Faraday.stub(:get, github_get_response(status: 200, body: "not json")) do
      assert_nil GithubEmails.primary_verified_email("token")
    end
  end

  [ 401, 403, 503 ].each do |status|
    test "HTTP #{status} 실패를 경고 로그에 남긴다" do
      output = StringIO.new
      Rails.stub(:logger, ActiveSupport::Logger.new(output)) do
        Faraday.stub(:get, github_get_response(status:, body: "private response")) do
          assert_nil GithubEmails.primary_verified_email("secret-token")
        end
      end

      assert_includes output.string, "GithubEmails: email lookup failed (HTTP #{status})"
      refute_includes output.string, "secret-token"
      refute_includes output.string, "private response"
    end
  end

  [ Faraday::ConnectionFailed, JSON::ParserError ].each do |error_class|
    test "#{error_class} 실패를 경고 로그에 남긴다" do
      output = StringIO.new
      Rails.stub(:logger, ActiveSupport::Logger.new(output)) do
        Faraday.stub(:get, ->(*) { raise error_class, "private response secret-token" }) do
          assert_nil GithubEmails.primary_verified_email("secret-token")
        end
      end

      assert_includes output.string, "GithubEmails: email lookup failed (#{error_class})"
      refute_includes output.string, "secret-token"
      refute_includes output.string, "private response"
    end
  end

  private

  def github_get_response(status:, body:)
    lambda do |_url, _params, _headers, &block|
      block.call(Struct.new(:options).new(Struct.new(:timeout, :open_timeout).new))
      Struct.new(:status, :body).new(status, body)
    end
  end
end
