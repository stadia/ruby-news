# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

module Articles
  module MetadataPreparation
    extend FunctionLogger

    TRACKING_QUERY_KEYS = %w[
      utm_source
      utm_medium
      utm_campaign
      _bhlid
      ref
      utm_content
      utm_term
      ck_subscriber_id
    ].freeze

    YOUTUBE_QUERY_KEYS = %w[t feature si].freeze

    class << self
      # 리다이렉트를 따라간 마지막 응답과 그 URL. 네트워크 오류면 nil.
      #: (String url) -> SafeHttp::Fetched?
      def fetch_url_content(url)
        SafeHttp.get_following_redirects(url)
      rescue Faraday::Error => e
        logger.error "Error fetching URL #{url}: #{e.message}"
        nil
      end

      #: (String url) -> ActiveSupport::TimeWithZone?
      def url_to_published_at(url)
        match_data = URI.parse(url).path&.match(%r{(\d{4})[/-](\d{1,2})[/-](\d{1,2})})
        return unless match_data

        Time.zone.parse("#{match_data[1]}-#{match_data[2]}-#{match_data[3]}")
      rescue URI::InvalidURIError
        logger.error "Invalid URI for published_at extraction: #{url}"
        nil
      rescue ArgumentError => e
        logger.error e
        nil
      end

      #: (String body) -> ActiveSupport::TimeWithZone?
      def extract_published_at_from_content(body)
        doc = Nokogiri::HTML(body)
        Articles::DateParsing.meta_published_at(doc) ||
          Articles::DateParsing.json_ld_published_at(doc) ||
          Articles::DateParsing.selector_published_at(doc) ||
          Articles::DateParsing.text_published_at(doc)
      rescue StandardError => e
        logger.error "Error parsing published_at: #{e.message}"
        nil
      end

      #: (Article article, String body) -> ActiveSupport::TimeWithZone
      def published_at_for(article, body)
        url = article.url
        candidate =
          article.published_at ||
          (url_to_published_at(url) if url.present?) ||
          extract_published_at_from_content(body)

        normalize_published_at(candidate)
      end

      #: (String title) -> String
      def build_slug(title)
        base = title.presence
        base ? base.parameterize.presence || random_slug : random_slug
      end

      #: (URI::Generic parsed_url) -> String
      def normalized_url(parsed_url)
        filtered_query_pairs = URI.decode_www_form(parsed_url.query.to_s)
                                  .reject { |key, _value| TRACKING_QUERY_KEYS.include?(key) }
        if parsed_url.host&.match?(/youtube/i)
          filtered_query_pairs.reject! { |key, _value| YOUTUBE_QUERY_KEYS.include?(key) }
        end

        # scheme과 호스트는 대소문자를 구분하지 않으므로 소문자로 맞춘다. 경로·쿼리는 구분할 수
        # 있어 그대로 둔다. URL 유니크 기준이 대소문자를 구분하므로 표기만 다른 같은 기사를 모은다.
        normalized = +"#{parsed_url.scheme&.downcase}://#{parsed_url.host&.downcase}#{parsed_url.path}"
        normalized << "?#{URI.encode_www_form(filtered_query_pairs)}" if filtered_query_pairs.any?
        normalized
      end

      #: (Article article, URI::Generic parsed_url) -> bool
      def should_discard_url?(article, parsed_url)
        path = parsed_url.path
        (!article.is_youtube && (path.nil? || path.size < 2)) ||
          Articles::Utils.should_ignore_url?(parsed_url.to_s)
      end

      #: (ActiveSupport::TimeWithZone? candidate) -> ActiveSupport::TimeWithZone
      def normalize_published_at(candidate)
        return Time.zone.now if candidate.nil?
        return Time.zone.now if candidate.future?

        candidate
      end

      private

      #: () -> String
      def random_slug
        "#{Time.zone.now.strftime('%Y%m%d')}-#{SecureRandom.hex(4)}"
      end
    end
  end
end
