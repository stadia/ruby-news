# frozen_string_literal: true

require "test_helper"

class BlogBodyTest < ActiveSupport::TestCase
  def attachment(url:, content_type: "image/*", alt: "", caption: "")
    %(<action-text-attachment url="#{url}" alt="#{alt}" caption="#{caption}" ) +
      %(content-type="#{content_type}" filename="x.webp" presentation="gallery"></action-text-attachment>)
  end

  test "에디터의 이미지 첨부를 figure, img, figcaption으로 바꾼다" do
    html = BlogBody.sanitize(attachment(url: "https://cdn.example/a.webp", alt: "대체 텍스트", caption: "사진 설명"))
    figure = Nokogiri::HTML5.fragment(html).at_css("figure")

    assert_not_nil figure, "figure가 없다: #{html}"
    assert_equal "https://cdn.example/a.webp", figure.at_css("img")["src"]
    assert_equal "대체 텍스트", figure.at_css("img")["alt"]
    assert_equal "사진 설명", figure.at_css("figcaption").text
    assert_not_includes html, "action-text-attachment"
  end

  test "alt가 비어 있으면 캡션을 alt로 쓰고, 캡션이 없으면 figcaption을 만들지 않는다" do
    with_caption = Nokogiri::HTML5.fragment(BlogBody.sanitize(attachment(url: "https://cdn.example/a.webp", caption: "설명")))
    without_caption = Nokogiri::HTML5.fragment(BlogBody.sanitize(attachment(url: "https://cdn.example/b.webp")))

    assert_equal "설명", with_caption.at_css("img")["alt"]
    assert_nil without_caption.at_css("figcaption")
    assert without_caption.at_css("figure img")
  end

  test "스토리지 리다이렉트 같은 상대 경로 이미지도 유지한다" do
    html = BlogBody.sanitize(attachment(url: "/rails/active_storage/blobs/redirect/abc/a.webp"))

    assert_equal "/rails/active_storage/blobs/redirect/abc/a.webp", Nokogiri::HTML5.fragment(html).at_css("img")["src"]
  end

  test "이미지가 아닌 첨부와 url이 없는 첨부는 버린다" do
    html = BlogBody.sanitize(
      "<p>앞</p>" +
      attachment(url: "https://cdn.example/a.pdf", content_type: "application/pdf") +
      %(<action-text-attachment content-type="image/*" caption="url 없음"></action-text-attachment>) +
      "<p>뒤</p>"
    )

    assert_equal "<p>앞</p><p>뒤</p>", html
  end

  test "http(s)나 상대 경로가 아닌 url의 첨부는 버린다" do
    html = BlogBody.sanitize(attachment(url: "javascript:alert(1)") + attachment(url: "data:image/png;base64,AAAA"))

    assert_equal "", html
  end

  test "섹션 제목과 구분선을 유지한다" do
    html = BlogBody.sanitize("<h2>큰 제목</h2><h3>작은 제목</h3><h4>더 작은 제목</h4><hr><p>본문</p>")

    assert_equal "<h2>큰 제목</h2><h3>작은 제목</h3><h4>더 작은 제목</h4><hr><p>본문</p>", html
  end

  test "허용하지 않는 태그와 style 속성은 지우고 글자는 남긴다" do
    html = BlogBody.sanitize(
      %(<h2><mark style="color: red;"><strong>제목</strong></mark></h2>) +
      %(<p onclick="x()">본문</p><iframe src="//evil.test/x"></iframe><script>alert(1)</script>)
    )

    assert_includes html, "<h2><strong>제목</strong></h2>"
    assert_includes html, "<p>본문</p>"
    assert_not_includes html, "style="
    assert_not_includes html, "onclick"
    assert_not_includes html, "evil.test"
    assert_not_includes html, "<script"
  end

  test "nil이나 빈 본문은 빈 문자열이 된다" do
    assert_equal "", BlogBody.sanitize(nil)
    assert_equal "", BlogBody.sanitize("")
  end
end
