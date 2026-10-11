# frozen_string_literal: true

# rbs_inline: enabled

require "test_helper"

class ContentServiceTest < ActiveSupport::TestCase
  # MockResponse 헬퍼 Struct
  MockResponse = Struct.new(:status, :body, :headers, keyword_init: true) do
    def initialize(status:, body: "", headers: {})
      super
    end
  end

  def setup
    # SCRAPLING_URL이 설정되어 있으면 mcp_fetch_html이 호출되어 Faraday stub이 무시됨
    ENV.delete("SCRAPLING_URL")
  end

  # HTML 콘텐츠 가져오기 테스트
  test "execute_html은 HTML 콘텐츠를 성공적으로 가져와 Readability로 파싱한다" do
    article = articles(:ruby_article)
    html_content = "<html><body><article><h1>Test Article</h1><p>This is the main content.</p></article></body></html>"

    service = ContentService.new

    service.stub(:faraday_fetch_html, html_content) do
      result = service.call(article)

      assert_predicate result, :success?
      assert_includes result.value!, "Test Article"
      assert_includes result.value!, "This is the main content."
    end
  end

  test "execute_html은 빈 콘텐츠일 때 Failure를 반환한다" do
    article = articles(:ruby_article)

    service = ContentService.new

    service.stub(:faraday_fetch_html, "") do
      result = service.call(article)

      assert_predicate result, :failure?
      assert_equal :no_content, result.failure
    end
  end

  test "execute_html은 faraday로 가져온 HTML을 파싱한다" do
    article = articles(:ruby_article)
    final_html = "<html><body><article><p>Final content</p></article></body></html>"

    service = ContentService.new

    service.stub(:faraday_fetch_html, final_html) do
      result = service.call(article)

      assert_predicate result, :success?
      assert_includes result.value!, "Final content"
    end
  end

  test "execute_html은 faraday 결과가 비어 있으면 Failure를 반환한다" do
    article = articles(:ruby_article)
    service = ContentService.new

    service.stub(:faraday_fetch_html, "") do
      result = service.call(article)

      assert_predicate result, :failure?
      assert_equal :no_content, result.failure
    end
  end

  test "execute_html은 내부망으로 리다이렉트되면 따라가지 않고 Failure를 반환한다" do
    article = Article.new(url: "https://example.com/redirect-me")
    requested = []
    redirect = MockResponse.new(status: 302, headers: { "location" => "http://127.0.0.1:3000/admin" })

    SafeHttp.stub(:fetch, ->(url, *) { requested << url && redirect }) do
      result = ContentService.new.call(article)

      assert_equal :blocked_url, result.failure
    end
    assert_equal [ "https://example.com/redirect-me" ], requested
  end

  test "execute_html은 SCRAPLING 경로에서 내부망으로 리다이렉트되면 넘기지 않는다" do
    article = Article.new(url: "https://example.com/redirect-me")
    redirect = MockResponse.new(status: 302, headers: { "location" => "http://10.0.0.5/secret" })

    ENV["SCRAPLING_URL"] = "http://scrapling.test/mcp"
    SafeHttp.stub(:fetch, ->(*) { redirect }) do
      MCPClient.stub(:connect, ->(*) { flunk "내부 주소는 넘기지 않아야 한다" }) do
        assert_equal :blocked_url, ContentService.new.call(article).failure
      end
    end
  ensure
    ENV.delete("SCRAPLING_URL")
  end

  test "execute_html은 SCRAPLING에 리다이렉트를 따라간 최종 URL을 넘긴다" do
    article = Article.new(url: "https://example.com/redirect-me")
    responses = [
      MockResponse.new(status: 301, headers: { "location" => "https://www.example.com/final" }),
      MockResponse.new(status: 200, body: "<html></html>")
    ]
    fetched = nil
    client = Object.new
    client.define_singleton_method(:call_tool) do |_name, args|
      fetched = args[:url]
      { "structuredContent" => { "status" => 200, "content" => [ "<html><body><article><p>Final</p></article></body></html>" ] } }
    end

    ENV["SCRAPLING_URL"] = "http://scrapling.test/mcp"
    SafeHttp.stub(:fetch, ->(*) { responses.shift }) do
      MCPClient.stub(:connect, client) do
        assert_predicate ContentService.new.call(article), :success?
      end
    end

    assert_equal "https://www.example.com/final", fetched
  ensure
    ENV.delete("SCRAPLING_URL")
  end

  test "execute_html은 SCRAPLING 경로에도 내부망 주소를 넘기지 않는다" do
    article = Article.new(url: "http://10.0.0.5/secret")

    ENV["SCRAPLING_URL"] = "http://scrapling.test/mcp"

    MCPClient.stub(:connect, ->(*) { flunk "내부 주소는 넘기지 않아야 한다" }) do
      assert_equal :blocked_url, ContentService.new.call(article).failure
    end
  ensure
    ENV.delete("SCRAPLING_URL")
  end

  # YouTube 콘텐츠 테스트
  test "execute_youtube는 YouTube transcript를 성공적으로 가져온다" do
    article = articles(:youtube_ruby_talk)

    service = ContentService.new

    # Yt::Video mock
    mock_caption = Struct.new(:language).new("en")
    mock_video = Object.new
    mock_video.define_singleton_method(:captions) { [ mock_caption ] }

    # Youtube::Transcript mock
    transcript_response = {
      "actions" => [
        {
          "updateEngagementPanelAction" => {
            "content" => {
              "transcriptRenderer" => {
                "content" => {
                  "transcriptSearchPanelRenderer" => {
                    "body" => {
                      "transcriptSegmentListRenderer" => {
                        "initialSegments" => [
                          {
                            "transcriptSegmentRenderer" => {
                              "startTimeText" => { "simpleText" => "00:00" },
                              "snippet" => { "runs" => [ { "text" => "Hello everyone" } ] }
                            }
                          },
                          {
                            "transcriptSegmentRenderer" => {
                              "startTimeText" => { "simpleText" => "00:05" },
                              "snippet" => { "runs" => [ { "text" => "Welcome to RubyConf" } ] }
                            }
                          }
                        ]
                      }
                    }
                  }
                }
              }
            }
          }
        }
      ]
    }

    stub_constructor(Yt::Video, ->(*, **) { mock_video }) do
      Youtube::Transcript.stub(:get, transcript_response) do
        result = service.call(article)

        assert_predicate result, :success?
        assert_includes result.value!, "Hello everyone"
        assert_includes result.value!, "Welcome to RubyConf"
      end
    end
  end

  test "execute_youtube는 YouTube URL이 아닌 경우 Failure를 반환한다" do
    # is_youtube?가 true이지만 URL에서 ID 추출 실패하는 경우
    article = Article.new(
      title: "Invalid YouTube",
      url: "https://invalid-url.com/not-youtube",
      origin_url: "https://invalid-url.com/not-youtube",
      is_youtube: true
    )

    service = ContentService.new
    result = service.call(article)

    assert_predicate result, :failure?
    assert_equal :not_youtube, result.failure
  end

  test "execute_youtube는 transcript가 없을 때 Failure를 반환한다" do
    article = articles(:youtube_ruby_talk)

    service = ContentService.new

    # Yt::Video mock - 빈 captions
    mock_video = Object.new
    mock_video.define_singleton_method(:captions) { [] }

    # YoutubeRb 백업도 실패
    mock_api = Object.new
    mock_api.define_singleton_method(:fetch) { |_| nil }

    stub_constructor(Yt::Video, ->(*, **) { mock_video }) do
      stub_constructor(YoutubeRb::Transcript::YouTubeTranscriptApi, ->(*, **) { mock_api }) do
        result = service.call(article)

        assert_predicate result, :failure?
        assert_equal :no_content, result.failure
      end
    end
  end

  test "execute_youtube는 YoutubeRb 백업을 사용한다" do
    article = articles(:youtube_ruby_talk)
    backup_transcript = "Backup transcript content"

    service = ContentService.new

    # Yt::Video mock - 빈 captions 반환
    mock_video = Object.new
    mock_video.define_singleton_method(:captions) { [] }

    # YoutubeRb 백업 성공
    mock_transcript_data = [ "segment1", "segment2" ]
    mock_api = Object.new
    mock_api.define_singleton_method(:fetch) { |_| mock_transcript_data }

    mock_formatter = Object.new
    mock_formatter.define_singleton_method(:format_transcript) { |_| backup_transcript }

    stub_constructor(Yt::Video, ->(*, **) { mock_video }) do
      stub_constructor(YoutubeRb::Transcript::YouTubeTranscriptApi, ->(*, **) { mock_api }) do
        stub_constructor(YoutubeRb::Formatters::TextFormatter, ->(*, **) { mock_formatter }) do
          result = service.call(article)

          assert_predicate result, :success?
          assert_equal backup_transcript, result.value!
        end
      end
    end
  end

  test "execute_youtube는 첫 번째 transcript API 오류 시 백업을 시도한다" do
    article = articles(:youtube_ruby_talk)
    backup_transcript = "Fallback transcript"

    service = ContentService.new

    # Yt::Video mock - captions 접근 시 에러
    mock_video = Object.new
    mock_video.define_singleton_method(:captions) { raise StandardError, "API Error" }

    # YoutubeRb 백업 성공
    mock_transcript_data = [ "segment" ]
    mock_api = Object.new
    mock_api.define_singleton_method(:fetch) { |_| mock_transcript_data }

    mock_formatter = Object.new
    mock_formatter.define_singleton_method(:format_transcript) { |_| backup_transcript }

    stub_constructor(Yt::Video, ->(*, **) { mock_video }) do
      stub_constructor(YoutubeRb::Transcript::YouTubeTranscriptApi, ->(*, **) { mock_api }) do
        stub_constructor(YoutubeRb::Formatters::TextFormatter, ->(*, **) { mock_formatter }) do
          result = service.call(article)

          assert_predicate result, :success?
          assert_equal backup_transcript, result.value!
        end
      end
    end
  end

  # 헬퍼 메서드 테스트
  test "is_youtube? 확인을 통해 올바른 메서드가 호출된다" do
    # 일반 기사
    regular_article = articles(:ruby_article)

    assert_not regular_article.is_youtube?

    # YouTube 기사
    youtube_article = articles(:youtube_ruby_talk)

    assert_predicate youtube_article, :is_youtube?
  end

  test "Youtube::Transcript 응답에 error가 있으면 다음 언어를 시도한다" do
    article = articles(:youtube_ruby_talk)

    service = ContentService.new

    # Yt::Video mock - 여러 언어의 captions
    mock_captions = [
      Struct.new(:language).new("ko"),
      Struct.new(:language).new("en")
    ]
    mock_video = Object.new
    mock_video.define_singleton_method(:captions) { mock_captions }

    call_count = 0
    # Youtube::Transcript mock - 첫 번째는 에러, 두 번째는 성공
    transcript_stub = ->(_id, **_opts) {
      call_count += 1
      if call_count == 1
        { "error" => "No transcript for this language" }
      else
        {
          "actions" => [
            {
              "updateEngagementPanelAction" => {
                "content" => {
                  "transcriptRenderer" => {
                    "content" => {
                      "transcriptSearchPanelRenderer" => {
                        "body" => {
                          "transcriptSegmentListRenderer" => {
                            "initialSegments" => [
                              {
                                "transcriptSegmentRenderer" => {
                                  "startTimeText" => { "simpleText" => "00:00" },
                                  "snippet" => { "runs" => [ { "text" => "English transcript" } ] }
                                }
                              }
                            ]
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          ]
        }
      end
    }

    stub_constructor(Yt::Video, ->(*, **) { mock_video }) do
      Youtube::Transcript.stub(:get, transcript_stub) do
        result = service.call(article)

        assert_predicate result, :success?
        assert_includes result.value!, "English transcript"
      end
    end

    assert_equal 2, call_count
  end

  test "github_readme_url은 tree 브랜치 URL을 raw README URL로 변환한다" do
    service = ContentService.new

    url = service.send(:github_readme_url, "https://github.com/rails/rails/tree/main")

    assert_equal "https://raw.githubusercontent.com/rails/rails/main/README.md", url
  end

  test "github_readme_url은 owner/repo가 없으면 nil을 반환한다" do
    service = ContentService.new

    assert_nil service.send(:github_readme_url, "https://github.com/rails")
    assert_nil service.send(:github_readme_url, "not a valid url")
  end

  test "github_url?은 github host와 raw host만 true를 반환한다" do
    service = ContentService.new

    assert service.send(:github_url?, "https://github.com/rails/rails")
    assert service.send(:github_url?, "https://raw.githubusercontent.com/rails/rails/main/README.md")
    assert_not service.send(:github_url?, "https://example.com/rails")
    assert_not service.send(:github_url?, "http://[")
  end

  test "faraday_fetch_html은 상대 경로 리다이렉트를 따라간다" do
    service = ContentService.new
    responses = [
      MockResponse.new(status: 302, headers: { "location" => "/redirected" }),
      MockResponse.new(status: 200, body: "<html>done</html>", headers: {})
    ]

    SafeHttp.stub(:fetch, ->(*) { responses.shift }) do
      assert_equal "<html>done</html>", service.send(:faraday_fetch_html, "https://example.com/original")
    end
  end

  test "faraday_fetch_html은 리다이렉트 제한을 넘기면 마지막 body를 반환한다" do
    service = ContentService.new
    response = MockResponse.new(status: 302, body: "stop", headers: { "location" => "https://example.com/next" })

    SafeHttp.stub(:fetch, ->(*) { response }) do
      assert_equal "stop", service.send(:faraday_fetch_html, "https://example.com/original", 4)
    end
  end

  test "mcp_fetch_html은 상태 코드가 200이 아니면 nil을 반환한다" do
    service = ContentService.new
    client = Object.new
    client.define_singleton_method(:call_tool) { |*, **| { "structuredContent" => { "status" => 500, "content" => [] } } }

    SafeHttp.stub(:fetch, ->(*) { MockResponse.new(status: 200) }) do
      MCPClient.stub(:connect, client) do
        assert_nil service.send(:mcp_fetch_html, "https://example.com")
      end
    end
  end

  test "mcp_fetch_html은 첫 번째 content 항목을 반환한다" do
    service = ContentService.new
    client = Object.new
    client.define_singleton_method(:call_tool) { |*, **| { "structuredContent" => { "status" => 200, "content" => [ "<html>ok</html>" ] } } }

    SafeHttp.stub(:fetch, ->(*) { MockResponse.new(status: 200) }) do
      MCPClient.stub(:connect, client) do
        assert_equal "<html>ok</html>", service.send(:mcp_fetch_html, "https://example.com")
      end
    end
  end

  test "format_transcript는 세그먼트가 없으면 nil을 반환한다" do
    service = ContentService.new

    assert_nil service.send(:format_transcript, nil)
    assert_nil service.send(:format_transcript, [])
  end
end
