# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

require "mcp_client"

class ContentService < OperationService
  include LinkHelper

  #: (Article article) -> Dry::Monads::Result
  def call(article)
    url = article.url.to_s

    if article.is_youtube?
      # YouTube URL인 경우
      step execute_youtube(url)
    elsif github_url?(url)
      # GitHub URL인 경우 README.md 가져오기
      step execute_github_readme(article)
    else
      # 일반 URL인 경우
      step execute_html(url)
    end
  end

  protected

  # Dry::Operation의 call에서 return Failure(...)를 직접 반환하면 Success(Failure(...))로 감싸지므로
  # guard clause는 반드시 step으로 호출되는 별도 메서드에 위치시킨다.
  #: (Article article) -> Dry::Monads::Result
  def execute_github_readme(article)
    readme_url = github_readme_url(article.url.to_s)
    return Failure(:no_content) unless readme_url

    logger.info "GitHub README URL: #{readme_url}"
    execute_html(readme_url)
  end

  #: (String url) -> Dry::Monads::Result
  def execute_html(url)
    logger.info "Fetching HTML content from: #{url}"

    html_content = if ENV.fetch("SCRAPLING_URL", nil).present?
                     mcp_fetch_html(url)
    else
                     faraday_fetch_html(url)
    end

    return Failure(:no_content) if html_content.blank?

    # Readability를 사용하여 주요 콘텐츠 HTML 추출. Readability::Document는 전체 HTML 문자열을 인자로 받습니다.
    github_url?(url) ? Success(Inkmark.to_html(html_content, options: { preset: :recommended })) : Success(Readability::Document.new(html_content).content)
  rescue SafeHttp::BlockedUrlError => e
    logger.warn e.message
    Failure(:blocked_url)
  end

  #: (String url) -> Dry::Monads::Result
  def execute_youtube(url)
    logger.info "Fetching Youtube content from: #{url}"
    youtube_id = youtube_id(url)
    logger.info "Youtube ID: #{youtube_id}"
    return Failure(:not_youtube) unless youtube_id

    # Declared up front, so without the annotation the local is pinned to
    # `nil` and every later assignment in the blocks below is rejected.
    transcript = nil #: String?
    video = Yt::Video.new id: youtube_id
    begin
      video.captions.map(&:language).each do |lang|
        rc = Youtube::Transcript.get(youtube_id, lang: lang)
        next if rc["error"].present?

        transcript = format_transcript(rc.dig("actions"))
        break if transcript.present?
      end
    rescue StandardError => e
      logger.error "Error fetching Youtube transcript: #{e.message}"
    end

    if transcript.blank?
      begin
        fetched_transcript = YoutubeRb::Transcript::YouTubeTranscriptApi.new.fetch(youtube_id)
        transcript = YoutubeRb::Formatters::TextFormatter.new.format_transcript(fetched_transcript) if fetched_transcript.present?
      rescue StandardError => e
        logger.error "Error fetching Youtube transcript: #{e.message}"
      end
    end

    return Failure(:no_content) if transcript.blank?

    Success(transcript)
  end

  private

  #: (String url) -> bool
  def github_url?(url)
    URI.parse(url).host&.match?(/\A(github\.com|raw\.githubusercontent\.com)\z/) == true
  rescue URI::InvalidURIError
    false
  end

  #: (String url) -> String?
  def github_readme_url(url)
    logger.info "Fetching GitHub README from: #{url}"
    uri = URI.parse(url)
    parts = uri.path.to_s.split("/").reject(&:blank?)
    owner, repo = parts
    return nil if owner.nil? || repo.nil?

    repo = repo.delete_suffix(".git")

    # branch가 URL에 명시된 경우: /owner/repo/tree/branch
    branch = parts[3] if parts[2] == "tree"
    branch ||= "HEAD"

    "https://raw.githubusercontent.com/#{owner}/#{repo}/#{branch}/README.md"
  rescue URI::InvalidURIError
    nil
  end

  #: (String url) -> String?
  def faraday_fetch_html(url)
    SafeHttp.get_following_redirects(url).response.body
  end

  #: (String url) -> String?
  def mcp_fetch_html(url)
    # Scrapling은 리다이렉트를 검사 없이 따라가므로, 앱에서 먼저 검사하며 따라간 최종 URL만 넘긴다.
    # shortcut: Scrapling이 다른 응답(UA별 리다이렉트, DNS 리바인딩)을 받으면 못 막는다. Scrapling 파드 egress 차단으로 보완한다.
    fetched = SafeHttp.get_following_redirects(url)
    response = fetched.response
    url = fetched.url
    # 리다이렉트 한도에 걸린 3xx는 Location을 검사하지 않았으므로 넘기지 않는다.
    return nil if response.status.between?(300, 399)

    client = MCPClient.connect(ENV.fetch("SCRAPLING_URL") { "http://localhost::8000/mcp" })
    result = client.call_tool("fetch", { url: })&.[]("structuredContent")
    logger.debug result
    return nil if result["status"] != 200

    result["content"].first
  end

  #: (Array[untyped]? actions) -> String?
  def format_transcript(actions)
    tsr = actions&.first&.dig("updateEngagementPanelAction", "content", "transcriptRenderer", "content", "transcriptSearchPanelRenderer", "body", "transcriptSegmentListRenderer", "initialSegments")
    return nil if tsr.nil? || tsr.empty?

    tsr.map { |it| "#{it.dig("transcriptSegmentRenderer", "startTimeText", "simpleText")} - #{it.dig("transcriptSegmentRenderer", "snippet", "runs")&.map { |run| run.dig("text") }&.join(" ")}" }.join("\n") # Use string interpolation for clarity
  end
end
