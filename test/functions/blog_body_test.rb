# frozen_string_literal: true

require "test_helper"

class BlogBodyTest < ActiveSupport::TestCase
  def attachment(url:, content_type: "image/*", alt: "", caption: "")
    %(<action-text-attachment url="#{url}" alt="#{alt}" caption="#{caption}" ) +
      %(content-type="#{content_type}" filename="x.webp" presentation="gallery"></action-text-attachment>)
  end

  def render_sanitize(html)
    ApplicationController.helpers.sanitize(html, scrubber: BlogBody::SCRUBBER).to_s
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

  test "툴바의 취소선·밑줄·표를 유지한다" do
    html = BlogBody.sanitize(
      "<p>a <s>취소</s> <u>밑줄</u></p>" +
      %(<figure class="lexxy-content__table-wrapper"><table><tbody><tr>) +
      %(<th class="lexxy-content__table-cell--header"><p>머리</p></th><td><p>칸</p></td>) +
      "</tr></tbody></table></figure>"
    )
    fragment = Nokogiri::HTML5.fragment(html)

    assert_equal "취소", fragment.at_css("p s").text
    assert_equal "밑줄", fragment.at_css("p u").text
    assert_equal "머리", fragment.at_css("figure.lexxy-content__table-wrapper table tr th.lexxy-content__table-cell--header").text
    assert_equal "칸", fragment.at_css("table tr td").text
  end

  test "글자색·배경색은 Lexxy 팔레트 변수만 mark에 남긴다" do
    html = BlogBody.sanitize(
      %(<p><mark style="color: var(--highlight-1);">색</mark>) +
      %(<mark style="background-color: var(--highlight-bg-2);color: var(--highlight-3)">둘</mark>) +
      %(<mark style="color: red; position: fixed">빨강</mark>) +
      %(<mark style="background: url(javascript:alert(1))">url</mark></p>) +
      %(<p style="color: var(--highlight-1)">문단</p>)
    )
    marks = Nokogiri::HTML5.fragment(html).css("mark")

    assert_equal "color: var(--highlight-1);", marks[0]["style"]
    assert_equal "background-color: var(--highlight-bg-2); color: var(--highlight-3);", marks[1]["style"]
    assert_nil marks[2]["style"]
    assert_nil marks[3]["style"]
    assert_includes html, "<p>문단</p>"
  end

  test "코드 블록 언어와 표 셀 병합은 해당 요소에 올바른 값일 때만 남긴다" do
    html = BlogBody.sanitize(
      %(<pre data-language="ruby" data-highlight-language="ruby">def a; end</pre>) +
      %(<pre data-language="x y">b</pre><p data-language="ruby">c</p>) +
      %(<table><tbody><tr><td colspan="2" rowspan="x">d</td><th colspan="0">e</th></tr></tbody></table>) +
      %(<p colspan="2">f</p>)
    )
    fragment = Nokogiri::HTML5.fragment(html)
    pres = fragment.css("pre")

    assert_equal %w[ruby ruby], [ pres[0]["data-language"], pres[0]["data-highlight-language"] ]
    assert_nil pres[1]["data-language"]
    assert_equal "2", fragment.at_css("td")["colspan"]
    assert_nil fragment.at_css("td")["rowspan"]
    assert_nil fragment.at_css("th")["colspan"]
    assert_equal "<p>c</p>", fragment.css("p").first.to_html
    assert_equal "<p>f</p>", fragment.css("p").last.to_html
  end

  test "코드 블록 언어와 표 셀 병합 값의 앞뒤 공백은 지워서 남긴다" do
    html = BlogBody.sanitize(
      %(<pre data-language=" ruby " data-highlight-language="ruby\n">a</pre>) +
      %(<table><tbody><tr><td colspan=" 2 " rowspan="3 ">b</td></tr></tbody></table>)
    )
    fragment = Nokogiri::HTML5.fragment(html)

    assert_equal %w[ruby ruby], [ fragment.at_css("pre")["data-language"], fragment.at_css("pre")["data-highlight-language"] ]
    assert_equal %w[2 3], [ fragment.at_css("td")["colspan"], fragment.at_css("td")["rowspan"] ]
  end

  test "서식이 있는 본문을 다시 정제해도 그대로다" do
    once = BlogBody.sanitize(
      %(<h2>제목</h2><p><s>a</s><u>b</u><mark style="color: var(--highlight-4);">c</mark></p>) +
      %(<pre data-language="ruby">d</pre><table><tbody><tr><th>e</th><td colspan="2">f</td></tr></tbody></table>)
    )

    assert_equal once, BlogBody.sanitize(once)
    assert_equal once, render_sanitize(once)
  end

  # 화면(Views::Posts::Show)은 Rails 헬퍼 sanitize로 같은 스크러버를 한 번 더 통과시킨다.
  # 헬퍼는 HTML5 파서를 쓰므로, 저장 경로도 같은 파서여야 두 결과가 같다.
  FORMATTED_BODIES = {
    "tbody 없는 표" => %(<figure class="lexxy-content__table-wrapper"><table><tr><th>머리</th><td>칸</td></tr></table></figure>),
    "thead만 있는 표" => "<table><thead><tr><th>h</th></tr></thead><tr><td>d</td></tr></table>",
    "빈 요소" => "<p></p><p><br></p><hr><h2></h2>",
    "중첩 리스트" => "<ul><li>a<ul><li>b</li></ul></li></ul><ol><li><p>x</p></li></ol>",
    "하이라이트" => %(<p><mark style="color: var(--highlight-1);">색</mark> a&nbsp;b</p>),
    "앞 줄바꿈이 있는 코드 블록" => %(<pre data-language="ruby">\n\nputs 1\n</pre>),
    "code 안의 앞 줄바꿈" => "<pre><code>\n\nx</code></pre>",
    "문단 안의 표" => "<p>a<table><tr><td>t</td></tr></table></p>"
  }.freeze

  test "저장 경로와 화면 경로가 같은 결과를 내고, 어느 쪽으로 다시 정제해도 그대로다" do
    FORMATTED_BODIES.each do |name, html|
      saved = BlogBody.sanitize(html)

      assert_equal saved, render_sanitize(html), name
      assert_equal saved, BlogBody.sanitize(saved), "#{name}: 저장 경로 멱등성"
      assert_equal saved, render_sanitize(saved), "#{name}: 화면 경로 멱등성"
    end
  end

  test "코드 블록 첫 줄의 빈 줄은 다시 정제해도 사라지지 않는다" do
    saved = BlogBody.sanitize(%(<pre data-language="ruby">\n\nputs 1</pre>))

    assert_equal "\nputs 1", Nokogiri::HTML5.fragment(saved).at_css("pre").text
    assert_equal "\nputs 1", Nokogiri::HTML5.fragment(render_sanitize(saved)).at_css("pre").text
  end

  test "이미지 첨부가 있는 코드 블록의 첫 빈 줄을 저장과 편집 왕복에서 보존한다" do
    saved = BlogBody.sanitize(attachment(url: "https://cdn.example/a.webp") + "<pre>\n\nx</pre>")

    assert_equal "\nx", Nokogiri::HTML5.fragment(saved).at_css("pre").text
    assert_equal "\nx", Nokogiri::HTML5.fragment(BlogBody.editor_value(saved)).at_css("pre").text
    assert_equal saved, BlogBody.sanitize(BlogBody.editor_value(saved))
  end

  test "figure 이미지가 있는 코드 블록도 편집 왕복에서 첫 빈 줄을 보존한다" do
    saved = BlogBody.sanitize(%(<figure><img src="https://cdn.example/a.webp" alt=""></figure><pre>\n\nx</pre>))

    assert_equal "\nx", Nokogiri::HTML5.fragment(BlogBody.editor_value(saved)).at_css("pre").text
    assert_equal saved, BlogBody.sanitize(BlogBody.editor_value(saved))
  end

  test "저장 정제기는 화면 sanitize 헬퍼의 vendor를 사용한다" do
    assert_equal ActionView::Helpers::SanitizeHelper.sanitizer_vendor.safe_list_sanitizer, BlogBody::SANITIZER
  end

  test "HTML4 정제는 코드 블록 첫 줄바꿈을 보존하며 멱등이다" do
    sanitizer = Rails::HTML4::SafeListSanitizer.new
    once = sanitizer.sanitize("<pre>\n\nx</pre>", scrubber: BlogBody::SCRUBBER)

    assert_equal "<pre>\n\nx</pre>", once
    assert_equal once, sanitizer.sanitize(once, scrubber: BlogBody::SCRUBBER)
  end

  test "HTML4로 정제되어 저장된 본문은 다시 정제하면 화면에 보이던 모양이 되고, 그 뒤로는 그대로다" do
    # 이전 BlogBody.sanitize(HTML4)가 표 행 안(셀 앞뒤)과 중첩 목록 뒤에 줄바꿈을 넣고 tbody는 넣지 않았던 형태.
    legacy = "<table><tr>\n<th>a</th>\n<td>b</td>\n</tr></table><ul><li>a<ul><li>b</li></ul>\n</li></ul>"

    resaved = BlogBody.sanitize(legacy)

    assert_equal render_sanitize(legacy), resaved
    assert_equal "<table><tbody><tr>\n<th>a</th>\n<td>b</td>\n</tr></tbody></table>", resaved[/<table>.*<\/table>/m]
    assert_equal resaved, BlogBody.sanitize(resaved)
  end

  test "허용하지 않는 태그와 style 속성은 지우고 글자는 남긴다" do
    html = BlogBody.sanitize(
      %(<h2><mark style="color: red;"><strong>제목</strong></mark></h2>) +
      %(<p onclick="x()">본문</p><iframe src="//evil.test/x"></iframe><script>alert(1)</script>)
    )

    assert_includes html, "<h2><mark><strong>제목</strong></mark></h2>"
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

  test "에디터 값: 저장된 이미지 figure를 캡션이 붙은 첨부로 되돌린다" do
    saved = BlogBody.sanitize(attachment(url: "https://cdn.example/a.webp?v=1", alt: "대체 텍스트", caption: "사진 설명"))
    node = Nokogiri::HTML5.fragment(BlogBody.editor_value(saved)).at_css("action-text-attachment")

    assert_not_nil node
    assert_equal "https://cdn.example/a.webp?v=1", node["url"]
    assert_equal "대체 텍스트", node["alt"]
    assert_equal "사진 설명", node["caption"]
    assert_equal "a.webp", node["filename"]
    assert node["content-type"].start_with?("image")
    assert_not_includes BlogBody.editor_value(saved), "figcaption"
  end

  test "에디터 값을 다시 저장해도 본문이 그대로다 — 저장할 때마다 캡션이 늘지 않는다" do
    saved = BlogBody.sanitize(
      "<p>앞</p>" + attachment(url: "https://cdn.example/a.webp", caption: "설명") +
      attachment(url: "/rails/active_storage/blobs/redirect/abc/b.png", alt: "b.png") + "<p>뒤</p>"
    )

    resaved = 3.times.reduce(saved) { |body, _| BlogBody.sanitize(BlogBody.editor_value(body)) }

    assert_equal saved, resaved
  end

  test "에디터 값: 이미지 figure가 든 표 wrapper는 표째 바꾸지 않고 안쪽 이미지만 첨부로 되돌린다" do
    saved = BlogBody.sanitize(
      %(<figure class="lexxy-content__table-wrapper"><table><tr><td>셀 텍스트</td><td>) +
      attachment(url: "/a.png", caption: "캡션") + %(</td></tr></table></figure>)
    )
    value = Nokogiri::HTML5.fragment(BlogBody.editor_value(saved))

    assert_includes value.text, "셀 텍스트"
    assert_equal "캡션", value.at_css("figure.lexxy-content__table-wrapper table td > action-text-attachment")&.[]("caption"), value.to_html
  end

  test "에디터 값: img·figcaption 말고 다른 내용이 있는 figure는 그대로 둔다" do
    [
      %(<figure><img src="/a.png" alt="a"><img src="/b.png" alt="b"><figcaption>둘</figcaption></figure>),
      %(<figure><a href="/x"><img src="/a.png" alt="a"></a></figure>),
      %(<figure><img src="/a.png" alt="a"><p>덧붙인 문단</p></figure>)
    ].each do |html|
      assert_equal html, BlogBody.editor_value(html)
    end
  end

  test "에디터 값: 캡션에서 채운 alt는 비워 넘겨, 캡션을 고치면 alt도 따라간다" do
    saved = BlogBody.sanitize(attachment(url: "https://cdn.example/a.webp", caption: "설명"))
    value = BlogBody.editor_value(saved)

    assert_equal "", Nokogiri::HTML5.fragment(value).at_css("action-text-attachment")["alt"]

    resaved = BlogBody.sanitize(value.sub('caption="설명"', 'caption="새 설명"'))

    assert_equal "새 설명", Nokogiri::HTML5.fragment(resaved).at_css("img")["alt"]
  end

  test "에디터 값: 이미지가 없는 figure와 figure 없는 본문은 그대로 둔다" do
    table = %(<figure class="lexxy-content__table-wrapper"><p>표</p></figure>)

    assert_equal table, BlogBody.editor_value(table)
    assert_equal "<p>본문</p>", BlogBody.editor_value("<p>본문</p>")
    assert_equal "", BlogBody.editor_value(nil)
  end
end
