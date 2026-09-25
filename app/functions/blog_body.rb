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
  end
end
