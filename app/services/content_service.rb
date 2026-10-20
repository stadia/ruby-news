# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

require "mcp_client"

class ContentService < OperationService
  include LinkHelper

  # 일시적 원인으로 본문을 얻지 못한 실패 사유. 다시 시도하면 얻을 수도 있으므로 호출자는
  # 폐기하지 않고 재시도 대상으로 다룬다.
  TRANSIENT_FAILURES = %i[fetch_failed].freeze
  # 5xx 외에 일시 실패로 보는 상태 코드(403 봇 차단일 수 있음, 408 요청 시간 초과, 429 요청 한도 초과).
  # 403은 진짜 접근 금지와 구분할 수 없지만, 폐기는 연합 Delete까지 전파되므로 보존 쪽으로 둔다.
  # 5xx는 범위라 usable_status?가 따로 비교한다.
  TRANSIENT_STATUSES = [ 403, 408, 429 ].freeze

  # 원 서버·Scrapling·YouTube가 잠시 응답하지 못했거나 일시적 상태 코드를 돌려줬다.
  # execute_html·execute_youtube가 :fetch_failed로 바꾼다.
  class TransientFetchError < StandardError; end

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
  # Faraday 예외는 연결 실패·타임아웃·SSL 오류 같은 전송 계층 오류다(HTTP 상태로는 예외가 나지
  # 않는다). 만료 인증서처럼 영구적인 것도 섞여 있지만 구분하기 어렵고 폐기는 되돌릴 수 없으므로
  # 일시 실패로 보수적으로 다룬다. 계속 실패하는 기사는 ArticleAgentsService가 error로 남긴다.
  rescue TransientFetchError, Faraday::Error => e
    logger.warn "Transient failure fetching #{url}: #{e.class}: #{e.message}"
    Failure(:fetch_failed)
  end

  #: (String url) -> Dry::Monads::Result
  def execute_youtube(url)
    logger.info "Fetching Youtube content from: #{url}"
    youtube_id = youtube_id(url)
    logger.info "Youtube ID: #{youtube_id}"
    return Failure(:not_youtube) unless youtube_id

    primary_failed = false
    begin
      transcript = primary_transcript(youtube_id)
    rescue StandardError => e
      primary_failed = true
      logger.warn "Primary YouTube transcript lookup failed for #{youtube_id}: #{e.class}: #{e.message}"
    end
    return Success(transcript) if transcript.present?

    transcript = backup_transcript(youtube_id)
    return Success(transcript) if transcript.present?

    # 백업이 예외 없이 비었더라도 1차 조회가 예외였다면 자막이 없다고 단정할 수 없다.
    Failure(primary_failed ? :fetch_failed : :no_content)
  # 백업 조회는 자막이 없다는 사실을 빈 값이 아니라 예외로 알린다. 영상 자체의 상태를 알리는
  # 예외만 영구 실패로 본다. PoTokenRequired·YouTubeDataUnparsable처럼 모든 영상에 걸릴 수
  # 있는 예외까지 영구로 보면 한꺼번에 폐기되므로 나머지는 일시 실패로 둔다.
  rescue YoutubeRb::Transcript::TranscriptsDisabled, YoutubeRb::Transcript::NoTranscriptFound,
         YoutubeRb::Transcript::NoTranscriptAvailable, YoutubeRb::Transcript::VideoUnavailable,
         YoutubeRb::Transcript::InvalidVideoId, YoutubeRb::Transcript::AgeRestricted,
         YoutubeRb::Transcript::VideoUnplayable => e
    logger.info "No YouTube transcript for #{youtube_id}: #{e.class}"
    Failure(:no_content)
  rescue YoutubeRb::Transcript::Error, Faraday::Error => e
    logger.warn "Backup YouTube transcript lookup failed for #{youtube_id}: #{e.class}: #{e.message}"
    Failure(:fetch_failed)
  end

  private

  # 언어별로 조회해 처음 얻은 자막을 돌려준다. 예외는 호출자가 일시 실패 판단에 쓴다.
  #: (String youtube_id) -> String?
  def primary_transcript(youtube_id)
    Yt::Video.new(id: youtube_id).captions.map(&:language).each do |lang|
      rc = Youtube::Transcript.get(youtube_id, lang: lang)
      next if rc["error"].present?

      transcript = format_transcript(rc.dig("actions"))
      return transcript if transcript.present?
    end
    nil
  end

  # 분류되지 않은 예외(코드 버그)는 삼키지 않고 올려, ArticleAgentsService가 클래스와 함께 남기게 한다.
  #: (String youtube_id) -> String?
  def backup_transcript(youtube_id)
    fetched = YoutubeRb::Transcript::YouTubeTranscriptApi.new.fetch(youtube_id)
    YoutubeRb::Formatters::TextFormatter.new.format_transcript(fetched) if fetched.present?
  end

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
    response = SafeHttp.get_following_redirects(url).response
    response.body if usable_status?(response.status)
  end

  # 2xx만 본문으로 쓴다. TRANSIENT_STATUSES와 5xx는 일시 실패라 TransientFetchError를 올리고, 그 밖의 4xx와
  # 따라가지 못한 3xx는 false를 돌려 :no_content(영구 실패)가 되게 한다. 오류 페이지를 요약하지
  # 않기 위해서다(#1099).
  #: (Integer status) -> bool
  def usable_status?(status)
    raise TransientFetchError, "HTTP #{status}" if TRANSIENT_STATUSES.include?(status) || status >= 500

    status.between?(200, 299)
  end

  #: (String url) -> String?
  def mcp_fetch_html(url)
    # 앱에서 리다이렉트를 검사하며 따라간 최종 URL만 넘기고, Scrapling에서는 더 따라가지 않는다.
    # shortcut: Scrapling의 DNS 리바인딩은 앱에서 못 막는다. Scrapling 파드 egress 차단으로 보완한다.
    fetched = SafeHttp.get_following_redirects(url)
    response = fetched.response
    url = fetched.url
    # 리다이렉트 한도에 걸린 3xx는 Location을 검사하지 않았으므로 넘기지 않는다. 그 밖의 상태는
    # 보지 않는다. 직접 요청에 403·503을 주는 안티봇 페이지를 넘기는 것이 Scrapling을 쓰는 이유다.
    return nil if response.status.between?(300, 399)

    client = MCPClient.connect(ENV.fetch("SCRAPLING_URL") { "http://localhost::8000/mcp" })
    result = client.call_tool("make_request", { url:, extraction_type: "html", follow_redirects: false })&.[]("structuredContent")
    logger.debug result
    raise TransientFetchError, "Scrapling returned no structuredContent for #{url}" unless result.is_a?(Hash)

    # Scrapling의 status는 브라우저가 받은 원 서버 응답이라 직접 요청과 같은 기준으로 나눈다.
    status = result["status"]
    raise TransientFetchError, "Scrapling returned status #{status.inspect}" unless status.is_a?(Integer)
    raise TransientFetchError, "Scrapling returned an unchecked redirect: HTTP #{status}" if status.between?(300, 399)
    return nil unless usable_status?(status)

    # 200인데 본문이 비면 Scrapling 쪽 렌더 실패로 보고 일시 실패로 둔다.
    body = Array(result["content"]).first
    raise TransientFetchError, "Scrapling returned empty content for #{url}" if body.blank?

    body
  end

  #: (Array[untyped]? actions) -> String?
  def format_transcript(actions)
    tsr = actions&.first&.dig("updateEngagementPanelAction", "content", "transcriptRenderer", "content", "transcriptSearchPanelRenderer", "body", "transcriptSegmentListRenderer", "initialSegments")
    return nil if tsr.nil? || tsr.empty?

    tsr.map { |it| "#{it.dig("transcriptSegmentRenderer", "startTimeText", "simpleText")} - #{it.dig("transcriptSegmentRenderer", "snippet", "runs")&.map { |run| run.dig("text") }&.join(" ")}" }.join("\n") # Use string interpolation for clarity
  end
end
