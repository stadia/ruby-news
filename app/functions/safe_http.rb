# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

# 사용자가 준 URL을 서버가 대신 요청할 때 쓴다. 내부망 주소와 http(s) 외 스킴을 막고 타임아웃을 건다.
# 리다이렉트는 get_following_redirects가 hop마다 get을 다시 불러 매 단계 검사한다.
module SafeHttp
  class BlockedUrlError < StandardError; end

  MAX_REDIRECTS = 4

  # IPAddr#private?/loopback?/link_local? 밖이지만 전역 라우팅 대상이 아닌 특수 용도 대역(IANA special-purpose)
  INTERNAL_RANGES = %w[
    0.0.0.0/8 100.64.0.0/10 192.0.0.0/24 192.0.2.0/24 192.88.99.0/24 198.18.0.0/15 198.51.100.0/24 203.0.113.0/24
    224.0.0.0/3
    ::/128 64:ff9b::/96 64:ff9b:1::/48 100::/64 2001::/23 2001:db8::/32 2002::/16 ff00::/8
  ].map { IPAddr.new(it) }.freeze

  class << self
    # 테스트가 고정 hosts resolver로 바꿔 실제 DNS를 쓰지 않게 한다.
    attr_writer :resolver

    #: (String url) -> Faraday::Response
    def get(url)
      fetch(url, check!(url))
    end

    # 3xx를 따라가 마지막 응답과 그 URL을 돌려준다. 상대 경로는 현재 URL 기준으로 풀고,
    # 상한에 걸리면 마지막 3xx 응답을 그대로 돌려준다(그 Location은 검사하지 않았다).
    #: (String url) -> [Faraday::Response, String]
    def get_following_redirects(url)
      response = get(url)
      MAX_REDIRECTS.times do
        location = response.headers["location"]
        break unless response.status.between?(300, 399) && location

        url = URI.join(url, location).to_s #: String
        response = get(url)
      end
      [ response, url ]
    end

    # 검사한 IP로 직접 연결해 DNS 리바인딩을 막는다. Host 헤더와 TLS SNI는 URL의 호스트를 그대로 쓴다.
    #: (String url, String ip) -> Faraday::Response
    def fetch(url, ip)
      connection(ip).get(url)
    end

    # 통과하면 연결할 IP를 돌려준다.
    #: (String url) -> String
    def check!(url)
      public_address(url) || raise(BlockedUrlError, "blocked URL: #{url}")
    end

    #: (String url) -> bool
    def public_url?(url)
      !public_address(url).nil?
    end

    #: (String host) -> Array[String]
    def resolve(host)
      resolver.getaddresses(host)
    end

    private

    # 풀리지 않거나 하나라도 내부 주소로 풀리면 nil. IPv6 경로가 없는 환경을 고려해 IPv4를 먼저 고른다.
    #: (String url) -> String?
    def public_address(url)
      uri = URI.parse(url)
      host = uri.hostname
      return unless %w[http https].include?(uri.scheme) && host.present?

      addresses = resolve(host)
      return if addresses.empty? || addresses.any? { internal?(IPAddr.new(it)) }

      addresses.min_by { it.include?(":") ? 1 : 0 }
    rescue URI::InvalidURIError, IPAddr::InvalidAddressError, Resolv::ResolvError, SystemCallError
      nil
    end

    #: (IPAddr ip) -> bool
    def internal?(ip)
      ip = ip.native
      ip.private? || ip.loopback? || ip.link_local? || INTERNAL_RANGES.any? { it.include?(ip) }
    end

    #: (String ip) -> Faraday::Connection
    def connection(ip)
      Faraday.new(request: { open_timeout: HttpTimeouts::OPEN, timeout: HttpTimeouts::REQUEST }) do |f|
        f.adapter(:net_http) { |http| http.ipaddr = ip }
      end
    end

    #: () -> Resolv
    def resolver
      @resolver ||= Resolv.new([ Resolv::Hosts.new, Resolv::DNS.new.tap { it.timeouts = HttpTimeouts::OPEN } ])
    end
  end
end
