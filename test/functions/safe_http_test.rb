# frozen_string_literal: true

require "test_helper"

class SafeHttpTest < ActiveSupport::TestCase
  test "public_url?은 내부망 주소와 http(s) 외 스킴을 거부한다" do
    %w[
      http://127.0.0.1/a
      http://localhost/a
      http://10.0.0.5/a
      http://192.168.1.150:8443/a
      http://169.254.169.254/latest
      http://0.0.0.0/a
      http://[::1]/a
      http://[::ffff:127.0.0.1]/a
      ftp://example.com/a
      file:///etc/passwd
      not\ a\ url
    ].each do |url|
      assert_not SafeHttp.public_url?(url), url
    end
  end

  test "public_url?은 호스트가 내부 주소로 풀리거나 풀리지 않으면 거부한다" do
    SafeHttp.stub(:resolve, [ "93.184.215.14", "10.0.0.5" ]) do
      assert_not SafeHttp.public_url?("https://mixed.example/a")
    end
    SafeHttp.stub(:resolve, []) do
      assert_not SafeHttp.public_url?("https://nowhere.example/a")
    end
  end

  test "public_url?은 공인 주소로 풀리는 http(s) URL을 허용한다" do
    SafeHttp.stub(:resolve, [ "93.184.215.14" ]) do
      assert SafeHttp.public_url?("https://blog.example/post")
    end
  end

  test "get은 차단된 URL을 요청하지 않고 BlockedUrlError를 던진다" do
    Faraday.stub(:get, ->(*) { flunk "내부 주소는 요청하지 않아야 한다" }) do
      assert_raises(SafeHttp::BlockedUrlError) { SafeHttp.get("http://192.168.1.150/admin") }
    end
  end

  test "get은 연결·요청 타임아웃을 건다" do
    options = Faraday::RequestOptions.new
    request = Struct.new(:options).new(options)
    response = Faraday::Response.new(status: 200, body: "ok")

    SafeHttp.stub(:resolve, [ "93.184.215.14" ]) do
      Faraday.stub(:get, ->(*_args, &block) { block.call(request) && response }) do
        assert_same response, SafeHttp.get("https://blog.example/post")
      end
    end

    assert_equal HttpTimeouts::OPEN, options.open_timeout
    assert_equal HttpTimeouts::REQUEST, options.timeout
  end
end
