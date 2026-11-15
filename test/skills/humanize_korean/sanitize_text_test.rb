# frozen_string_literal: true

require "test_helper"
require Rails.root.join("app/skills/humanize-korean/scripts/sanitize_text").to_s

# upstream tests/test_sanitize.py(v2.3.2)의 Ruby 포트. 비가시 문자는 리터럴로 쓰지 않는다.
class HumanizeKoreanSanitizeTextTest < ActiveSupport::TestCase
  ZWSP = 0x200B.chr(Encoding::UTF_8)
  BOM = 0xFEFF.chr(Encoding::UTF_8)
  SHY = 0x00AD.chr(Encoding::UTF_8)
  WJ = 0x2060.chr(Encoding::UTF_8)
  NBSP = 0x00A0.chr(Encoding::UTF_8)
  IDEO = 0x3000.chr(Encoding::UTF_8)
  NARROW_NBSP = 0x202F.chr(Encoding::UTF_8)
  RLO = 0x202E.chr(Encoding::UTF_8)
  LRM = 0x200E.chr(Encoding::UTF_8)
  ZWJ = 0x200D.chr(Encoding::UTF_8)
  ZWNJ = 0x200C.chr(Encoding::UTF_8)
  TAG_A = 0xE0061.chr(Encoding::UTF_8)
  LINE_SEP = 0x2028.chr(Encoding::UTF_8)
  PARA_SEP = 0x2029.chr(Encoding::UTF_8)

  def sanitize(...) = HumanizeKoreanSanitize.sanitize(...)

  test "정상 한국어는 건드리지 않는다" do
    clean = [
      "AI가 쓴 글을 사람 글처럼 다듬습니다.",
      "",
      "첫째, 번역투를 걷어냅니다. 둘째, 리듬을 살립니다.",
      "가격은 1,200원이며 — 부가세 별도입니다.",
      '그는 "그렇게는 못 한다"고 잘라 말했다.',
      "이모지도 그대로: 👨#{ZWJ}👩#{ZWJ}👧 가족"
    ].join("\n")
    out, report = sanitize(clean)

    assert_equal clean, out
    assert_not report.changed?
    assert_equal "", report.summary
  end

  test "제로폭·BOM·소프트하이픈·워드조이너를 제거한다" do
    out, report = sanitize("안#{ZWSP}녕#{BOM}하#{SHY}세#{WJ}요")

    assert_equal "안녕하세요", out
    assert_equal 4, report.counts["invisible"]
    assert_operator report.after_chars, :<, report.before_chars
  end

  test "이모지 ZWJ는 보존하고 한글 사이 joiner는 제거한다" do
    emoji = "👨#{ZWJ}👩#{ZWJ}👧"

    assert_equal emoji, sanitize(emoji).first

    out, report = sanitize("한#{ZWJ}글#{ZWNJ}테스트")

    assert_equal "한글테스트", out
    assert_equal 2, report.counts["invisible"]
  end

  test "bidi 제어 문자와 태그 문자를 제거한다" do
    out, report = sanitize("정상#{RLO}뒤집기#{LRM}끝")

    assert_equal "정상뒤집기끝", out
    assert_equal 2, report.counts["bidi"]

    out, report = sanitize("본문#{TAG_A}#{TAG_A}끝")

    assert_equal "본문끝", out
    assert_equal 2, report.counts["tag_chars"]
  end

  test "분해된 한글을 NFC로 결합한다" do
    nfd = "한글 테스트".unicode_normalize(:nfd)
    out, report = sanitize(nfd)

    assert_equal "한글 테스트", out
    assert_equal 5, report.counts["hangul_recomposed"]
  end

  test "특수 공백은 보통 공백으로, 전각공백은 기본 보존한다" do
    out, report = sanitize("가#{NBSP}나#{IDEO}다#{NARROW_NBSP}라")

    assert_equal "가 나#{IDEO}다 라", out
    assert_equal 2, report.counts["special_spaces"]

    out, report = sanitize("가#{IDEO}나", normalize_ideographic_space: true)

    assert_equal "가 나", out
    assert_equal 1, report.counts["special_spaces"]
  end

  test "줄바꿈을 LF로 통일하고 줄 끝 공백을 지우며 빈 줄은 기본 보존한다" do
    out, report = sanitize("첫 줄   \r\n둘째 줄#{LINE_SEP}셋째 줄#{PARA_SEP}\n\n\n\n넷째 줄")

    assert_equal "첫 줄\n둘째 줄\n셋째 줄\n\n\n\n\n넷째 줄", out
    assert_operator report.counts["line_breaks"], :>=, 3
    assert_operator report.counts["trailing_space_lines"], :>=, 1
    assert_equal "가\n\n나", sanitize("가\n\n\n\n나", collapse_blank_lines: true).first
    assert_equal "가\n\n\n\n나", sanitize("가\n\n\n\n나").first
  end

  # upstream과 다른 로컬 규칙: summary_body는 마크다운이라 두 칸 이상 공백 강제 줄바꿈은 의미가 있다.
  test "마크다운 강제 줄바꿈의 줄 끝 공백은 보존한다" do
    out, report = sanitize("첫 번째 줄  \n두 번째 줄 \n세 번째 줄\t\n끝   ")

    assert_equal "첫 번째 줄  \n두 번째 줄\n세 번째 줄\n끝", out
    assert_equal 3, report.counts["trailing_space_lines"]
    assert_equal out, sanitize(out).first
  end

  test "멱등이다" do
    dirty = "안#{ZWSP}녕#{NBSP}하세요#{RLO}\r\n\r\n\r\n#{"둘째".unicode_normalize(:nfd)}   \n#{TAG_A}"
    once, = sanitize(dirty)
    twice, report = sanitize(once)

    assert_equal once, twice
    assert_not report.changed?
  end

  test "옵션을 개별로 끌 수 있다" do
    dirty = "가#{NBSP}나#{ZWSP}다"

    assert_equal "가 나#{ZWSP}다", sanitize(dirty, strip_invisible: false).first
    assert_includes sanitize(dirty, normalize_spaces: false).first, NBSP
  end

  test "보호 토큰은 그대로 남는다" do
    src = "2026년 8월 2일, EU AI Act 발효.#{ZWSP} 앤트로픽은 #{NBSP}\"별도 문자를 추가하지 않는다\"고 밝혔다. 수치는 4,500개."
    out, = sanitize(src)

    [ "2026", "8월 2일", "EU AI Act", "앤트로픽", "4,500", "별도 문자를 추가하지 않는다" ].each do |token|
      assert_includes out, token
    end
  end

  test "빈 입력을 처리한다" do
    out, report = sanitize("")

    assert_equal "", out
    assert_not report.changed?
    assert_equal "\n\n", sanitize("   \n  \n").first
  end

  test "소스에 리터럴 비가시 문자가 없다" do
    source = Rails.root.join("app/skills/humanize-korean/scripts/sanitize_text.rb").read(encoding: "UTF-8")
    bad = source.each_char.reject { |char| "\n\t".include?(char) }.select do |char|
      code = char.ord
      char.match?(/\p{Cf}|\p{Cc}|\p{Co}|\p{Cs}/) || [ 0xA0, 0x3000, 0x2028, 0x2029 ].include?(code) || (0x2000..0x200F).cover?(code)
    end

    assert_empty bad
  end
end
