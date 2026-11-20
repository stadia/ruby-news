# frozen_string_literal: true

require "test_helper"
require "active_storage/service/s3_service"

class R2CorsTest < ActiveSupport::TestCase
  def s3_service
    ActiveStorage::Service::S3Service.new(
      bucket: "ruby-news-test",
      endpoint: "https://account.r2.cloudflarestorage.com",
      region: "auto",
      access_key_id: "test",
      secret_access_key: "test",
      stub_responses: true
    )
  end

  test "규칙은 에디터를 여는 두 사이트에서 오는 PUT만 허용한다" do
    rule = R2Cors.configuration[:cors_rules].sole

    assert_equal %w[https://ruby-news.dev https://ruby-news.jp], rule[:allowed_origins]
    assert_equal %w[PUT], rule[:allowed_methods]
  end

  test "허용 헤더가 direct upload PUT에 실리는 헤더를 모두 덮는다" do
    headers = s3_service.headers_for_direct_upload(
      "key", content_type: "image/png", checksum: "abc==",
      filename: ActiveStorage::Filename.new("a.png"), disposition: :inline
    )
    allowed = R2Cors::ALLOWED_HEADERS.map(&:downcase)

    assert_empty headers.keys.map(&:downcase) - allowed, "CORS에 없는 헤더가 있으면 preflight에서 막힌다"
  end

  test "ACTIVE_STORAGE_CORS_ORIGINS로 출처를 더할 수 있다" do
    ENV["ACTIVE_STORAGE_CORS_ORIGINS"] = " https://staging.ruby-news.dev , https://ruby-news.dev ,"

    assert_equal %w[https://ruby-news.dev https://ruby-news.jp https://staging.ruby-news.dev], R2Cors.origins
  ensure
    ENV.delete("ACTIVE_STORAGE_CORS_ORIGINS")
  end

  test "apply!는 서비스의 버킷에 규칙을 넣는다" do
    service = s3_service
    R2Cors.apply!(service)
    request = service.bucket.client.api_requests.sole

    assert_equal :put_bucket_cors, request[:operation_name]
    assert_equal "ruby-news-test", request[:params][:bucket]
    assert_equal R2Cors.configuration, request[:params][:cors_configuration]
  end

  test "current_rules는 CORS 설정이 없는 버킷이면 빈 배열이다" do
    service = s3_service
    service.bucket.client.stub_responses(:get_bucket_cors, "NoSuchCORSConfiguration")

    assert_equal [], R2Cors.current_rules(service)
  end

  test "current_rules는 다른 오류를 삼키지 않는다" do
    service = s3_service
    service.bucket.client.stub_responses(:get_bucket_cors, "AccessDenied")

    assert_raises(Aws::S3::Errors::AccessDenied) { R2Cors.current_rules(service) }
  end
end
