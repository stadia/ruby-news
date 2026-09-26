# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

# 블로그(장문) 본문의 정제 규칙. 단문·댓글용 HtmlSanitizable::ALLOWED_TAGS에
# 블로그 에디터(Lexxy)가 만드는 섹션 제목·이미지·구분선만 더한다.
#
# Lexxy는 본문 이미지를 <img>가 아니라 <action-text-attachment url=…>로 직렬화한다.
# 이 앱은 ActionText를 쓰지 않아 그 태그를 렌더링할 방법이 없고 허용 목록에도 없으므로,
# 정제 전에 <figure><img><figcaption>으로 바꿔 둔다. 그대로 두면 태그째 지워진다.
module BlogBody
  ALLOWED_TAGS = (HtmlSanitizable::ALLOWED_TAGS + %w[h2 h3 h4 hr figure figcaption]).freeze
  IMAGE_URL = %r{\A(https?://|/)}i

  class << self
    #: (String?) -> String
    def sanitize(html)
      Rails::Html::SafeListSanitizer.new.sanitize(expand_image_attachments(html.to_s), tags: ALLOWED_TAGS).to_s
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
