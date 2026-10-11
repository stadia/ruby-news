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
end
