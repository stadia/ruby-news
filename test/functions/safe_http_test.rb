# frozen_string_literal: true

require "test_helper"

class SafeHttpTest < ActiveSupport::TestCase
  PUBLIC_IP = "93.184.215.14"

  test "public_url?은 내부·특수 용도 주소와 http(s) 외 스킴을 거부한다" do
    %w[
      http://127.0.0.1/a
      http://10.0.0.5/a
      http://198.51.100.1:8443/a
      http://169.254.169.254/latest
      http://0.0.0.0/a
      http://100.64.0.1/a
      http://198.18.0.1/a
      http://192.0.0.1/a
      http://[::1]/a
      http://[::ffff:127.0.0.1]/a
      http://[64:ff9b::7f00:1]/a
      http://[2002:7f00:1::1]/a
      http://[2001:db8::1]/a
      http://[64:ff9b:1::a00:5]/a
      http://[100::1]/a
      http://[2001::1]/a
      http://192.88.99.1/a
      ftp://example.com/a
      file:///etc/passwd
      not\ a\ url
    ].each do |url|
      assert_not SafeHttp.public_url?(url), url
    end
  end

  test "public_url?은 숫자형·축약형 IPv4 호스트를 거부한다" do
    %w[http://2130706433/a http://0x7f000001/a http://127.1/a http://0/a].each do |url|
      assert_not SafeHttp.public_url?(url), url
    end
  end

  test "public_url?은 호스트명이 내부 주소로 풀리면 거부한다" do
    SafeHttp.stub(:resolve, [ "127.0.0.1" ]) do
      assert_not SafeHttp.public_url?("https://internal.example/a")
    end
    SafeHttp.stub(:resolve, [ PUBLIC_IP, "10.0.0.5" ]) do
      assert_not SafeHttp.public_url?("https://mixed.example/a")
    end
    SafeHttp.stub(:resolve, []) do
      assert_not SafeHttp.public_url?("https://nowhere.example/a")
    end
  end

  test "public_url?은 DNS 조회가 실패하면 예외 없이 거부한다" do
    SafeHttp.stub(:resolve, ->(_host) { raise Errno::ENETUNREACH }) do
      assert_not SafeHttp.public_url?("https://blog.example/post")
    end
  end

  test "public_url?은 공인 주소로 풀리는 http(s) URL을 허용한다" do
    SafeHttp.stub(:resolve, [ PUBLIC_IP ]) do
      assert SafeHttp.public_url?("https://blog.example/post")
    end
  end

  test "get은 차단된 URL을 요청하지 않고 BlockedUrlError를 던진다" do
    SafeHttp.stub(:fetch, ->(*) { flunk "내부 주소는 요청하지 않아야 한다" }) do
      assert_raises(SafeHttp::BlockedUrlError) { SafeHttp.get("http://10.0.0.5/admin") }
    end
  end

  test "get은 검사한 IP로 요청한다" do
    pinned = nil

    SafeHttp.stub(:resolve, [ "2606:2800:21f:cb07:6820:80da:af6b:8b2c", PUBLIC_IP ]) do
      SafeHttp.stub(:fetch, ->(_url, ip) { pinned = ip }) do
        SafeHttp.get("https://blog.example/post")
      end
    end

    assert_equal PUBLIC_IP, pinned
  end

  # 호스트명은 풀리지 않지만 고정한 IP로 연결되고, Host 헤더는 원래 호스트를 유지한다.
  test "fetch는 지정한 IP로 연결하고 타임아웃을 건다" do
    server = TCPServer.new("127.0.0.1", 0)
    request_head = nil
    thread = Thread.new do
      socket = server.accept
      request_head = socket.readpartial(4096)
      socket.write("HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok")
      socket.close
    end

    response = SafeHttp.fetch("http://pinned.invalid:#{server.addr[1]}/path", "127.0.0.1")
    thread.join(5)

    assert_equal "ok", response.body
    assert_match(/^host: pinned\.invalid:\d+\r$/i, request_head)
  ensure
    server&.close
  end

  test "connection은 HttpTimeouts를 적용한다" do
    options = SafeHttp.send(:connection, PUBLIC_IP).options

    assert_equal HttpTimeouts::OPEN, options.open_timeout
    assert_equal HttpTimeouts::REQUEST, options.timeout
  end

  Response = Struct.new(:status, :headers, :body)

  test "get_following_redirects는 상대·절대 경로를 현재 URL 기준으로 따라가 마지막 응답과 URL을 돌려준다" do
    responses = [
      Response.new(301, { "location" => "/step-1" }, ""),
      Response.new(302, { "location" => "https://cdn.example/final" }, ""),
      Response.new(200, {}, "done")
    ]
    requested = []

    SafeHttp.stub(:resolve, [ PUBLIC_IP ]) do
      SafeHttp.stub(:fetch, ->(url, _ip) { requested << url; responses.shift }) do
        result = SafeHttp.get_following_redirects("https://blog.example/a/original")

        assert_equal "done", result.response.body
        assert_equal "https://cdn.example/final", result.url
      end
    end

    assert_equal %w[https://blog.example/a/original https://blog.example/step-1 https://cdn.example/final], requested
  end

  test "get_following_redirects는 상한을 넘으면 마지막 3xx 응답에서 멈춘다" do
    loop_response = Response.new(302, { "location" => "/again" }, "stop")
    count = 0

    SafeHttp.stub(:resolve, [ PUBLIC_IP ]) do
      SafeHttp.stub(:fetch, ->(*) { count += 1; loop_response }) do
        assert_equal 302, SafeHttp.get_following_redirects("https://blog.example/loop").response.status
      end
    end

    assert_equal SafeHttp::MAX_REDIRECTS + 1, count
  end

  # URI.join은 Location 전체를 파싱하므로 한글·공백이 든 값에서 InvalidURIError가 난다.
  # 예외 대신 다른 차단과 같은 BlockedUrlError로 다뤄야 호출부의 blocked_url 처리가 동작한다.
  test "get_following_redirects는 파싱할 수 없는 Location을 BlockedUrlError로 처리한다" do
    [ "https://blog.example/한글/글", "/한글/글", "https://blog.example/a b" ].each do |location|
      SafeHttp.stub(:resolve, [ PUBLIC_IP ]) do
        SafeHttp.stub(:fetch, ->(*) { Response.new(302, { "location" => location }, "") }) do
          assert_raises(SafeHttp::BlockedUrlError, location) { SafeHttp.get_following_redirects("https://blog.example/a") }
        end
      end
    end
  end

  test "get_following_redirects는 Location이 없는 3xx 응답을 그대로 돌려준다" do
    SafeHttp.stub(:resolve, [ PUBLIC_IP ]) do
      SafeHttp.stub(:fetch, ->(*) { Response.new(304, {}, "") }) do
        result = SafeHttp.get_following_redirects("https://blog.example/a")

        assert_equal 304, result.response.status
        assert_equal "https://blog.example/a", result.url
      end
    end
  end

  test "get_following_redirects는 내부망으로 가는 리다이렉트를 막는다" do
    SafeHttp.stub(:resolve, ->(host) { host == "blog.example" ? [ PUBLIC_IP ] : [ "10.0.0.5" ] }) do
      SafeHttp.stub(:fetch, ->(*) { Response.new(302, { "location" => "http://internal.example/admin" }, "") }) do
        assert_raises(SafeHttp::BlockedUrlError) { SafeHttp.get_following_redirects("https://blog.example/a") }
      end
    end
  end
end
