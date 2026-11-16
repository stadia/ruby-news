# frozen_string_literal: true

require "test_helper"

# #1161: 요약 모델이 관련 기사 링크의 주소를 example.com 자리표시자로 쓴 경우를 고친다.
class Articles::PlaceholderLinksTest < ActiveSupport::TestCase
  def repair(text) = Articles::PlaceholderLinks.repair(text)

  test "가짜 호스트에 붙은 실제 기사 경로는 상대 경로로 바꾼다" do
    assert_equal "앞 [제목](/articles/ruby-3-4-features) 뒤",
                 repair("앞 [제목](https://example.com/articles/ruby-3-4-features) 뒤")
    assert_equal "[제목](/articles/ruby-3-4-features)", repair("[제목](https://www.example.org/articles/ruby-3-4-features)")
  end

  test "없거나 삭제된 기사 경로면 링크만 지우고 문구를 남긴다" do
    assert_equal "앞 제목 뒤", repair("앞 [제목](https://example.com/articles/no-such-slug) 뒤")
    assert_equal "제목", repair("[제목](https://example.com/articles/deleted-article)")
  end

  test "호스트만 있으면 링크 텍스트와 제목이 정확히 하나 일치할 때만 잇는다" do
    assert_equal "[Ruby 3.4의 놀라운 새 기능들](/articles/ruby-3-4-features)",
                 repair("[Ruby 3.4의 놀라운 새 기능들](https://example.com)")
    assert_equal "모르는 제목", repair("[모르는 제목](https://example.com/)")

    articles(:korean_content_article).update_columns(title_ko: articles(:ruby_article).title_ko)

    assert_equal "Ruby 3.4의 놀라운 새 기능들", repair("[Ruby 3.4의 놀라운 새 기능들](https://example.com)")
  end

  test "기사 경로가 아닌 가짜 주소는 링크만 지운다" do
    assert_equal "구성 가이드 참고", repair("[구성 가이드](https://example.com/configuration-guide) 참고")
  end

  test "일본어 번역의 『제목』（주소） 형태도 마크다운 링크로 되돌린다" do
    assert_equal "[題名](/articles/ruby-3-4-features)", repair("『題名』（https://example.com/articles/ruby-3-4-features）")
    assert_equal "[題名](/articles/ruby-3-4-features)でも", repair("[題名]（https://example.com/articles/ruby-3-4-features）でも")
    assert_equal "『題名』といった", repair("『題名』（https://example.com）といった")
  end

  test "일본어 제목은 title_ja로 찾는다" do
    articles(:ruby_article).update_columns(title_ja: "Ruby 3.4の新機能")

    assert_equal "[Ruby 3.4の新機能](/articles/ruby-3-4-features)", repair("『Ruby 3.4の新機能』（https://example.com）")
  end

  test "코드 블록과 인라인 코드, 실제 주소는 건드리지 않는다" do
    text = <<~MD
      ```ruby
      link = "[a](https://example.com)"
      ```
      `[b](https://example.com/articles/ruby-3-4-features)` 와 [c](https://ruby-news.dev/articles/x), [d](/articles/y)
      http.get("https://example.com")
    MD

    assert_equal text, repair(text)
  end

  test "더 긴 펜스와 들여쓰기 코드 블록 안도 건드리지 않는다" do
    text = "````md\n```\n[x](https://example.com/articles/ruby-3-4-features)\n```\n````\n" \
           "~~~~\n~~~\n[y](https://example.com)\n~~~\n~~~~\n" \
           "예시:\n\n    [문서](https://example.com/configuration-guide)\n\t[탭](https://example.com)\n"

    assert_equal text, repair(text)
  end

  test "펜스 밖으로 나오면 다시 고친다" do
    assert_equal "````\n[a](https://example.com)\n````\n[제목](/articles/ruby-3-4-features)",
                 repair("````\n[a](https://example.com)\n````\n[제목](https://example.com/articles/ruby-3-4-features)")
  end

  test "정보 문자열이 붙은 펜스 줄은 닫는 펜스가 아니고, 들여쓴 중첩 목록은 고친다" do
    fenced = "```\n```ruby\n[x](https://example.com)\n```\n"

    assert_equal fenced, repair(fenced)
    assert_equal "- 상위\n    - [제목](/articles/ruby-3-4-features)\n",
                 repair("- 상위\n    - [제목](https://example.com/articles/ruby-3-4-features)\n")
  end

  test "이미지는 건드리지 않는다" do
    assert_equal "![스크린샷](https://example.com/a.png)", repair("![스크린샷](https://example.com/a.png)")
  end

  test "미확정 기사로는 잇지 않는다" do
    articles(:ruby_article).update_columns(title_ko: nil)

    assert_equal "제목", repair("[제목](https://example.com/articles/ruby-3-4-features)")
  end

  test "repair_all은 드라이런에서 바꿀 내용만 보고하고 저장하지 않는다" do
    article = articles(:korean_content_article)
    article.update_columns(summary_body: "[관련](https://example.com/articles/ruby-3-4-features)")

    changes = Articles::PlaceholderLinks.repair_all(write: false)

    assert_equal [ [ article.id, "summary_body", "[관련](/articles/ruby-3-4-features)" ] ],
                 changes.map { [ it.article_id, it.attribute, it.after ] }
    assert_includes article.reload.summary_body, "example.com"
  end

  test "repair_all은 쓰기 모드에서 윤문 상태를 건드리지 않고 컬럼만 고친다" do
    article = articles(:korean_content_article)
    article.update_columns(summary_body_ja: "『関連』（https://example.com）", humanize_status: { "state" => "applied" })

    Articles::PlaceholderLinks.repair_all(write: true)

    assert_equal "『関連』", article.reload.summary_body_ja
    assert_equal({ "state" => "applied" }, article.humanize_status)
    assert_empty Articles::PlaceholderLinks.repair_all(write: false)
  end

  test "nil과 빈 문자열은 그대로 돌려주고 결과는 멱등이다" do
    assert_nil repair(nil)
    assert_equal "", repair("")

    once = repair("[제목](https://example.com/articles/ruby-3-4-features) [x](https://example.com)")

    assert_equal once, repair(once)
  end
end
