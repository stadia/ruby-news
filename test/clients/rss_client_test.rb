# frozen_string_literal: true

require "test_helper"
require "rss"

class RssClientTest < ActiveSupport::TestCase
  test "RssClient는 모듈이다" do
    assert_kind_of Module, RssClient
  end

  test "feed 싱글톤 메서드를 가진다" do
    assert_respond_to RssClient, :feed
  end

  test "정상 RSS XML을 파싱한다" do
    xml = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Test Feed</title>
          <item>
            <title>Hello</title>
            <link>https://example.com/1</link>
          </item>
        </channel>
      </rss>
    XML

    result = RssClient.parse(xml)

    assert_kind_of RSS::Rss, result
    assert_equal "Test Feed", result.channel.title
  end

  test "RSS 1.0 RDF XML을 파싱한다" do
    xml = <<~XML
      <?xml version="1.0"?>
      <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns="http://purl.org/rss/1.0/">
        <channel rdf:about="https://example.com/">
          <title>RDF Feed</title>
          <link>https://example.com/</link>
          <description>Example feed</description>
          <items><rdf:Seq /></items>
        </channel>
      </rdf:RDF>
    XML

    result = RssClient.parse(xml)

    assert_kind_of RSS::RDF, result
    assert_equal "RDF Feed", result.channel.title
  end

  test "content 네임스페이스 누락 XML도 파싱한다" do
    xml = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Broken Feed</title>
          <item>
            <title>Hello</title>
            <content:encoded><![CDATA[<p>Body</p>]]></content:encoded>
          </item>
        </channel>
      </rss>
    XML

    result = RssClient.parse(xml)

    assert_kind_of RSS::Rss, result
    assert_equal "Broken Feed", result.channel.title
  end

  test "dc 네임스페이스 누락 XML도 파싱한다" do
    xml = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>DC Feed</title>
          <item>
            <title>Hello</title>
            <dc:creator>John</dc:creator>
          </item>
        </channel>
      </rss>
    XML

    result = RssClient.parse(xml)

    assert_kind_of RSS::Rss, result
    assert_equal "DC Feed", result.channel.title
  end

  test "여러 네임스페이스가 누락된 XML도 파싱한다" do
    xml = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Multi NS Feed</title>
          <item>
            <title>Hello</title>
            <content:encoded>Body</content:encoded>
            <dc:creator>John</dc:creator>
            <media:content url="https://example.com/img.jpg"/>
          </item>
        </channel>
      </rss>
    XML

    result = RssClient.parse(xml)

    assert_kind_of RSS::Rss, result
    assert_equal "Multi NS Feed", result.channel.title
  end

  test "알 수 없는 네임스페이스 접두어도 파싱한다" do
    xml = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Unknown NS Feed</title>
          <item>
            <title>Hello</title>
            <custom:tag>Value</custom:tag>
          </item>
        </channel>
      </rss>
    XML

    result = RssClient.parse(xml)

    assert_kind_of RSS::Rss, result
    assert_equal "Unknown NS Feed", result.channel.title
  end

  test "well-formed XML은 repair_xml을 호출하지 않는다" do
    xml = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
        <channel>
          <title>Good Feed</title>
          <item>
            <title>Hello</title>
            <content:encoded>Body</content:encoded>
          </item>
        </channel>
      </rss>
    XML

    RssClient.stub(:repair_xml, ->(_) { flunk "repair_xml should not be called" }) do
      result = RssClient.parse(xml)

      assert_kind_of RSS::Rss, result
    end
  end

  # 피드 요청도 SafeHttp를 거쳐 hop마다 검사하고 상대 경로 리다이렉트를 따라간다(#1062).
  test "feed는 SafeHttp로 리다이렉트를 따라가 피드를 파싱한다" do
    xml = <<~XML
      <?xml version="1.0"?>
      <rss version="2.0"><channel><title>Moved</title><link>https://blog.example</link><description>d</description></channel></rss>
    XML
    responses = [ Struct.new(:status, :headers, :body).new(301, { "location" => "/feed.xml" }, ""),
                  Struct.new(:status, :headers, :body).new(200, {}, xml) ]
    requested = []

    SafeHttp.stub(:resolve, [ "93.184.215.14" ]) do
      SafeHttp.stub(:fetch, ->(url, _ip) { requested << url; responses.shift }) do
        assert_equal "Moved", RssClient.feed("https://blog.example/rss").channel.title
      end
    end

    assert_equal %w[https://blog.example/rss https://blog.example/feed.xml], requested
  end
end
