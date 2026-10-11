# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

require "rss"
require "nokogiri"

module RssClient
  # RSS/Atom 피드에서 자주 누락되는 XML 네임스페이스
  KNOWN_NAMESPACES = {
    "content" => "http://purl.org/rss/1.0/modules/content/",
    "dc" => "http://purl.org/dc/elements/1.1/",
    "atom" => "http://www.w3.org/2005/Atom",
    "media" => "http://search.yahoo.com/mrss/",
    "slash" => "http://purl.org/rss/1.0/modules/slash/",
    "wfw" => "http://wellformedweb.org/CommentAPI/",
    "feedburner" => "http://rssnamespace.org/feedburner/ext/1.0",
    "sy" => "http://purl.org/rss/1.0/modules/syndication/",
    "admin" => "http://webns.net/mvcb/",
    "rdf" => "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
  }.freeze
  private_constant :KNOWN_NAMESPACES

  class << self
    #: (String url) -> (RSS::Rss | RSS::RDF | RSS::Atom::Feed)?
    def feed(url)
      response, = SafeHttp.get_following_redirects(url)
      raise Faraday::ForbiddenError, response.body if response.status == 403
      raise Faraday::UnauthorizedError, response.body if response.status == 401
      raise Faraday::TooManyRequestsError, response.body if response.status == 429
      parse(response.body)
    end

    #: (String xml) -> (RSS::Rss | RSS::RDF | RSS::Atom::Feed)?
    def parse(xml)
      return nil if xml.blank?

      RSS::Parser.parse(xml, false)
    rescue RSS::NotWellFormedError
      repaired = repair_xml(xml)
      return nil if repaired.blank? || repaired == xml

      RSS::Parser.parse(repaired, false)
    end

    #: (String xml) -> String
    def repair_xml(xml)
      doc = Nokogiri::XML(xml)
      root = doc.at("rss") || doc.at("feed") || doc.root
      return xml unless root

      doc.errors.each do |error|
        if error.to_s =~ /Namespace prefix (\w+) on/i
          prefix = $1
          uri = KNOWN_NAMESPACES[prefix] || "http://unknown.namespace/#{prefix}"
          root["xmlns:#{prefix}"] = uri
        end
      end

      doc.to_xml
    end
  end
end
