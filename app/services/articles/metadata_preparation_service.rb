# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

module Articles
  class MetadataPreparationService < OperationService
    #: (Article article) -> Dry::Monads::Result
    def call(article)
      step validate_article_url(article)

      step normalize_article_url(article)
      response = step resolve_response(article)
      if article.is_youtube?
        step apply_youtube_metadata(article)
      else
        step apply_webpage_metadata(article, response.body)
      end
      step ensure_article_slug(article)
    end

    private

    # Dry::Operation의 call에서 return Failure(...)를 직접 반환하면 Success(Failure(...))로 감싸지므로
    # guard clause는 반드시 step으로 호출되는 별도 메서드에 위치시킨다.
    #: (Article article) -> Dry::Monads::Result
    def validate_article_url(article)
      if article.url.blank? || !article.url.is_a?(String)
        return Failure(article)
      end
      Success(article)
    end

    #: (Article article) -> Dry::Monads::Result
    def resolve_response(article)
      response, final_url = MetadataPreparation.fetch_url_content(article.url.to_s)
      return Failure(:fetch_failed) if response.nil?

      article.url = final_url
      Success(response)
    rescue SafeHttp::BlockedUrlError => e
      logger.warn e.message
      Failure(:blocked_url)
    end

    #: (Article article) -> Dry::Monads::Result
    def normalize_article_url(article)
      parsed_url = URI.parse(article.url.to_s)
      article.url = MetadataPreparation.normalized_url(parsed_url)
      article.host = parsed_url.host
      article.is_youtube = parsed_url.host&.match?(/youtube/i) == true
      article.deleted_at = Time.zone.now if MetadataPreparation.should_discard_url?(article, parsed_url)
      Success(article)
    rescue URI::InvalidURIError
      logger.error "Invalid URI for initial URL parsing: #{article.url}"
      article.deleted_at = Time.zone.now
      Failure(:invalid_uri)
    end

    #: (Article article) -> Dry::Monads::Result
    def apply_youtube_metadata(article)
      video = Yt::Video.new id: article.youtube_id
      article.published_at = video.published_at if video.published_at.is_a?(Time)
      article.title = video.title if video.title.is_a?(String)
      Success(article)
    rescue Yt::Error => e
      logger.error "YouTube API error for video ID #{article.youtube_id}: #{e.message}"
      Failure(:api_error)
    end

    #: (Article article, String body) -> Dry::Monads::Result
    def apply_webpage_metadata(article, body)
      logger.debug "Setting webpage metadata for #{article.url}"
      return Failure(:discarded) if article.deleted_at.present?

      article.published_at = MetadataPreparation.published_at_for(article, body)
      return Success(article) if article.title.present?

      doc = Nokogiri::HTML5(body)
      temp_title = doc.at("title")&.text
      article.title = temp_title.strip.gsub(/\s+/, " ") if temp_title.is_a?(String)
      Success(article)
    rescue Nokogiri::XML::SyntaxError, ArgumentError => e
      logger.error "Error parsing webpage metadata for #{article.url}: #{e.message}"
      Failure(:parsing_error)
    end


    #: (Article article) -> Dry::Monads::Result
    def ensure_article_slug(article)
      return Success(article) if article.slug.present?

      article.slug = MetadataPreparation.build_slug(article.title.to_s)
      article.slug = "#{article.slug}-#{SecureRandom.hex(4)}" if Article.exists?(slug: article.slug)
      Success(article)
    end
  end
end
