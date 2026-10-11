# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

# 사용자가 준 URL을 서버가 대신 요청할 때 쓴다. 내부망 주소와 http(s) 외 스킴을 막고 타임아웃을 건다.
# 리다이렉트는 호출부가 hop마다 다시 get을 부르므로 매 단계 검사된다.
module SafeHttp
  class BlockedUrlError < StandardError; end

  # IPAddr#private?/loopback?/link_local? 밖이지만 외부로 나가지 않는 대역
  INTERNAL_RANGES = %w[0.0.0.0/8 100.64.0.0/10 224.0.0.0/3 ::/128 ff00::/8].map { IPAddr.new(it) }.freeze

  class << self
    #: (String url) -> Faraday::Response
    def get(url)
      check!(url)
      Faraday.get(url) do |req|
        req.options.open_timeout = HttpTimeouts::OPEN
        req.options.timeout = HttpTimeouts::REQUEST
      end
    end

    #: (String url) -> void
    def check!(url)
      raise BlockedUrlError, "blocked URL: #{url}" unless public_url?(url)
    end

    #: (String url) -> bool
    def public_url?(url)
      uri = URI.parse(url)
      host = uri.hostname
      return false unless %w[http https].include?(uri.scheme) && host.present?

      addresses = resolve(host)
      addresses.any? && addresses.none? { internal?(IPAddr.new(it)) }
    rescue URI::InvalidURIError, IPAddr::InvalidAddressError
      false
    end

    # shortcut: 검사한 IP로 직접 연결하지 않아 DNS 리바인딩은 막지 못한다. 필요해지면 검사한 IP로 연결하도록 바꾼다.
    #: (String host) -> Array[String]
    def resolve(host)
      Resolv.getaddresses(host)
    end

    private

    #: (IPAddr ip) -> bool
    def internal?(ip)
      ip = ip.native
      ip.private? || ip.loopback? || ip.link_local? || INTERNAL_RANGES.any? { it.include?(ip) }
    end
  end
end
