# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

# 블로그(장문) 본문의 정제 규칙. 단문·댓글용 HtmlSanitizable::ALLOWED_TAGS에
# 블로그 에디터(Lexxy) 툴바가 만드는 서식만 더한다.
#
# Lexxy는 본문 이미지를 <img>가 아니라 <action-text-attachment url=…>로 직렬화한다.
# 이 앱은 ActionText를 쓰지 않아 그 태그를 렌더링할 방법이 없고 허용 목록에도 없으므로,
# 정제 전에 <figure><img><figcaption>으로 바꿔 둔다. 그대로 두면 태그째 지워진다.
module BlogBody
  # 섹션 제목·구분선·이미지, 취소선·밑줄·글자색/배경색, 표.
  ALLOWED_TAGS = (
    HtmlSanitizable::ALLOWED_TAGS +
    %w[h2 h3 h4 hr figure figcaption s u mark table thead tbody tr th td]
  ).freeze
  IMAGE_URL = %r{\A(https?://|/)}i

  # 기본 허용 속성 밖에서 서식에 필요한 속성. 요소를 가려서만 남긴다.
  ELEMENT_ATTRIBUTES = {
    "mark" => %w[style],                                    # 글자색·배경색
    "pre" => %w[data-language data-highlight-language],     # 코드 블록 언어
    "td" => %w[colspan rowspan],
    "th" => %w[colspan rowspan]
  }.freeze

  # Lexxy 색 팔레트(var(--highlight-N), var(--highlight-bg-N))만 받는다.
  HIGHLIGHT_DECLARATION = /\A(?:color:\s*var\(--highlight-[1-9]\)|background-color:\s*var\(--highlight-bg-[1-9]\))\z/
  CODE_LANGUAGE = /\A[a-z0-9+#-]{1,32}\z/i
  CELL_SPAN = /\A[1-9][0-9]?\z/

  # ELEMENT_ATTRIBUTES 중 값 형식을 확인하는 속성. style은 scrub_css_attribute가 따로 본다.
  ATTRIBUTE_VALUES = {
    "data-language" => CODE_LANGUAGE,
    "data-highlight-language" => CODE_LANGUAGE,
    "colspan" => CELL_SPAN,
    "rowspan" => CELL_SPAN
  }.freeze

  # Rails 기본 허용 속성에 ELEMENT_ATTRIBUTES를 요소별로 더하는 스크러버.
  class Scrubber < Rails::Html::PermitScrubber
    ELEMENT_ONLY = ELEMENT_ATTRIBUTES.values.flatten.uniq.freeze

    def initialize
      super
      self.tags = ALLOWED_TAGS
      self.attributes = Rails::Html::SafeListSanitizer.allowed_attributes.to_a + ELEMENT_ONLY
    end

    protected

    #: (Nokogiri::XML::Node) -> void
    def scrub_attributes(node)
      allowed = ELEMENT_ATTRIBUTES.fetch(node.name, [])
      (ELEMENT_ONLY - allowed).each { |name| node.remove_attribute(name) }
      ATTRIBUTE_VALUES.each { |name, pattern| normalize_value(node, name, pattern) }
      super
    end

    # Loofah의 CSS 정제는 var()를 값째 지워서 Lexxy 색이 사라진다. style은
    # mark에만 남아 있으므로 선언마다 Lexxy 팔레트 형식인지 직접 확인한다.
    #: (Nokogiri::XML::Node) -> void
    def scrub_css_attribute(node)
      style = node["style"]
      return if style.nil?

      declarations = style.split(";").map(&:strip).select { |declaration| declaration.match?(HIGHLIGHT_DECLARATION) }
      if declarations.empty?
        node.remove_attribute("style")
      else
        node["style"] = declarations.map { |declaration| "#{declaration};" }.join(" ")
      end
    end

    private

    # 앞뒤 공백을 뺀 값이 형식에 맞으면 그 값으로 다시 쓰고, 아니면 속성을 지운다.
    #: (Nokogiri::XML::Node, String, Regexp) -> void
    def normalize_value(node, name, pattern)
      value = node[name]&.strip
      return if value.nil?

      value.match?(pattern) ? node[name] = value : node.remove_attribute(name)
    end
  end

  SCRUBBER = Scrubber.new

  class << self
    #: (String?) -> String
    def sanitize(html)
      Rails::Html::SafeListSanitizer.new.sanitize(expand_image_attachments(html.to_s), scrubber: SCRUBBER).to_s
    end

    # 저장된 본문을 에디터에 다시 넣을 값으로 바꾼다. Lexxy는 <img>만 이미지로 읽고
    # <figcaption>은 일반 문단으로 가져오므로, 저장본의 <figure>를 그대로 넣으면
    # 캡션이 본문 문단으로 한 벌 더 생기고 저장할 때마다 한 벌씩 늘어난다.
    # 이미지 figure를 Lexxy가 직렬화하는 첨부 태그로 되돌려 캡션이 첨부에 붙게 한다.
    #: (String?) -> String
    def editor_value(html)
      html = html.to_s
      return html unless html.include?("<figure")

      fragment = Nokogiri::HTML5.fragment(html)
      fragment.css("figure").each do |figure|
        attachment = image_attachment(figure)
        figure.replace(attachment) if attachment
      end
      fragment.to_html
    end

    private

    #: (String) -> String
    def expand_image_attachments(html)
      return html unless html.include?("<action-text-attachment")

      fragment = Nokogiri::HTML5.fragment(html)
      fragment.css("action-text-attachment").each do |node|
        figure = image_figure(node)
        figure ? node.replace(figure) : node.remove
      end
      fragment.to_html
    end

    # 이미지가 아니거나 http(s)·상대 경로가 아닌 url이면 nil — 호출부가 첨부를 버린다.
    #: (Nokogiri::XML::Element) -> Nokogiri::XML::Element?
    def image_figure(node)
      url = node["url"].to_s.strip
      return unless node["content-type"].to_s.start_with?("image") && url.match?(IMAGE_URL)

      caption = node["caption"].to_s.strip
      document = node.document
      figure = document.create_element("figure")
      figure.add_child(document.create_element("img", src: url, alt: node["alt"].presence || caption))
      figure.add_child(document.create_element("figcaption", caption)) if caption.present?
      figure
    end

    # image_figure가 만든 모양(img 하나 + figcaption 0~1개)의 figure만 첨부로 되돌린다.
    # 그 밖의 figure(표를 감싼 것, img가 여럿이거나 다른 내용이 섞인 것)는 nil — 통째로
    # 바꾸면 나머지 내용이 사라지므로 그대로 둔다. 안쪽 이미지 figure는 따로 변환된다.
    # image_figure가 캡션으로 채운 alt는 비워 넘겨, 캡션을 고치면 alt도 다시 따라가게 한다.
    #: (Nokogiri::XML::Element) -> Nokogiri::XML::Element?
    def image_attachment(figure)
      return unless image_figure_shape?(figure)

      img, figcaption = figure.element_children.to_a
      caption = figcaption&.text.to_s.strip
      src = img["src"].to_s
      alt = img["alt"].to_s
      figure.document.create_element(
        "action-text-attachment",
        "url" => src,
        "alt" => alt == caption ? "" : alt,
        "caption" => caption,
        "content-type" => "image/*",
        "filename" => src.split(/[?#]/).first.to_s.split("/").last.to_s,
        "presentation" => "gallery"
      )
    end

    #: (Nokogiri::XML::Element) -> bool
    def image_figure_shape?(figure)
      return false if figure.children.any? { |child| child.text? && child.text.strip.present? }

      names = figure.element_children.map(&:name)
      names.first == "img" && (names.drop(1) == [] || names.drop(1) == [ "figcaption" ])
    end
  end
end
