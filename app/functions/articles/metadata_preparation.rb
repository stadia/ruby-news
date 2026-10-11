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

    MAX_REDIRECTS = 3

    class << self
      #: (String url) -> Faraday::Response?
      def fetch_url_content(url)
        SafeHttp.get(url)
      rescue Faraday::Error => e
        logger.error "Error fetching URL #{url}: #{e.message}"
        nil
      end

      #: (Article article, Faraday::Response? response, ?Integer count) -> Faraday::Response?
      def follow_redirection(article, response, count = 0)
        return response if response.nil?
        return response unless response.status.between?(300, 399) && response.headers["location"]
        return response if count > MAX_REDIRECTS

        redirect_url = response.headers["location"]
        # article.url은 nilable 컬럼이라 상대 URL은 기준 URL이 있을 때만 해석한다.
        base_url = article.url
        current_url = if redirect_url.start_with?("http")
          redirect_url
        else
          if base_url.nil? || base_url.empty?
            logger.error "Cannot resolve relative redirect #{redirect_url.inspect} without an article URL"
            return nil
          end

          URI.join(base_url, redirect_url).to_s
        end
        article.url = current_url

        next_response = fetch_url_content(current_url)
        follow_redirection(article, next_response, count + 1)
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

        normalized = +"#{parsed_url.scheme}://#{parsed_url.host}#{parsed_url.path}"
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
