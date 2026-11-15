#!/usr/bin/env ruby
# typed: false
# frozen_string_literal: true
# rbs_inline: enabled

# 텍스트 위생(sanitize) — 결정적 처리, LLM 호출 0회.
#
# upstream scripts/sanitize_text.py(v2.3.2)의 Ruby 포트다. 규칙을 바꾸면 upstream과 같이 맞춘다.
#
# 하는 일: 눈에 보이지 않으면서 실제로 문제를 일으키는 문자를 정리한다.
#   - 한글 자모 분해(NFD) → 완성형(NFC). macOS 경유 텍스트는 자모로 분해된 경우가 많아
#     글자수·검색과 변경률 게이트(철칙 #4)가 어긋난다.
#   - 제로폭 문자·BOM·소프트하이픈, 양방향 제어 문자, 태그 문자(U+E0000~) 제거.
#   - NBSP 등 특수 공백 → 보통 공백. CRLF·유니코드 줄바꿈 → LF, 줄 끝 공백 제거.
#
# 하지 않는 일:
#   - AI 워터마크를 제거하지 않는다. 워터마크는 숨은 문자가 아니라 단어 선택의 통계 패턴에 실린다.
#   - 맞춤법·띄어쓰기·문장부호를 고치지 않고, 글자를 추가하거나 바꾸지 않는다.
#
# 설계 원칙: 멱등이고 표준 라이브러리만 쓴다. 소스에 비가시 문자를 리터럴로 쓰지 않는다.
# 전부 코드포인트로 조립한다(리터럴은 파일을 오염시키고 diff 리뷰를 불가능하게 한다).

require "json"
require "optparse"

module HumanizeKoreanSanitize
  Report = Data.define(:changed, :before_chars, :after_chars, :counts, :summary)

  class Report
    def changed? = changed
  end

  class << self
    # 코드포인트·범위 목록 → 정규식 문자 클래스
    def char_class(*ranges)
      body = ranges.map do |range|
        range.is_a?(Range) ? "\\u{#{range.begin.to_s(16)}}-\\u{#{range.end.to_s(16)}}" : "\\u{#{range.to_s(16)}}"
      end.join
      Regexp.new("[#{body}]")
    end
  end

  # 항상 제거해도 안전한 비가시 문자: 소프트하이픈, 몽골어 모음 구분자, ZWSP, 워드조이너, BOM
  INVISIBLE_ALWAYS = char_class(0x00AD, 0x180E, 0x200B, 0x2060, 0xFEFF)
  BIDI = char_class(0x061C, 0x200E..0x200F, 0x202A..0x202E, 0x2066..0x2069)
  # 태그 문자 — 숨은 텍스트 삽입 외 쓰임이 없다
  TAG_CHARS = char_class(0xE0000..0xE007F)
  # 특수 공백 → 보통 공백. 전각공백(U+3000)은 눈에 보이는 폭이라 제외하고 옵션으로 켠다.
  SPECIAL_SPACES = char_class(0x00A0, 0x1680, 0x2000..0x200A, 0x202F, 0x205F)
  IDEOGRAPHIC_SPACE = char_class(0x3000)
  UNI_BREAKS = char_class(0x2028, 0x2029)
  # 조합용 한글 자모(초성 + 중성 + 선택적 종성)
  DECOMPOSED_HANGUL = Regexp.new(
    "#{char_class(0x1100..0x1112).source}#{char_class(0x1161..0x1175).source}#{char_class(0x11A8..0x11C2).source}?"
  )
  # ZWJ/ZWNJ는 이모지 결합에 필수라, 양옆이 모두 평범한 문자일 때만 잘라낸다.
  PLAIN_NEIGHBOR = /\A[가-힣0-9A-Za-z\s.,!?;:'"()\[\]{}-]\z/
  JOINERS = [ 0x200C, 0x200D ].map { |code| code.chr(Encoding::UTF_8) }.freeze

  COUNT_KEYS = %w[hangul_recomposed invisible bidi tag_chars special_spaces line_breaks trailing_space_lines].freeze
  SUMMARY_LABELS = {
    "hangul_recomposed" => "분해된 한글 %d자 결합",
    "invisible" => "보이지 않는 문자 %d개 제거",
    "bidi" => "방향 제어 문자 %d개 제거",
    "tag_chars" => "숨은 태그 문자 %d개 제거",
    "special_spaces" => "특수 공백 %d개 정리",
    "line_breaks" => "줄바꿈 %d개 통일",
    "trailing_space_lines" => "줄 끝 공백 %d줄 정리"
  }.freeze

  class << self
    # 텍스트 위생 처리. [정리된 텍스트, Report]를 돌려준다.
    # normalize_ideographic_space·collapse_blank_lines는 고장이 아닌데 눈에 보이는 것을 바꾸므로
    # 철칙 #1(의미 불변)과 충돌하지 않도록 기본 off다.
    # rubocop:disable Metrics/ParameterLists
    def sanitize(text, normalize_unicode: true, strip_invisible: true, normalize_spaces: true,
                 normalize_lines: true, normalize_ideographic_space: false, collapse_blank_lines: false)
      # rubocop:enable Metrics/ParameterLists
      original = text
      counts = COUNT_KEYS.to_h { |key| [ key, 0 ] }

      # 비가시 문자는 정규화보다 먼저 지운다. 자모 사이에 낀 제로폭이 NFC 결합을 막는다.
      text = strip_invisibles(text, counts) if strip_invisible
      if normalize_unicode
        counts["hangul_recomposed"] = text.scan(DECOMPOSED_HANGUL).size
        text = text.unicode_normalize(:nfc)
      end
      text = replace_counted(text, SPECIAL_SPACES, " ", counts, "special_spaces") if normalize_spaces
      text = replace_counted(text, IDEOGRAPHIC_SPACE, " ", counts, "special_spaces") if normalize_ideographic_space
      text = normalize_line_breaks(text, counts) if normalize_lines
      text = text.gsub(/\n{3,}/, "\n\n") if collapse_blank_lines

      changed = text != original
      [ text, Report.new(changed:, before_chars: original.length, after_chars: text.length, counts:,
                         summary: summary(counts, changed)) ]
    end

    # 텍스트를 바꾸지 않고 무엇이 걸리는지만 센다.
    def inspect_text(text, **) = sanitize(text, **).last

    def main(argv = ARGV)
      options = { in_place: false, report: false }
      parser = OptionParser.new do |opts|
        opts.banner = "usage: ruby sanitize_text.rb [PATH] [--in-place] [--report] (워터마크 제거 아님)"
        opts.on("--in-place", "파일을 제자리에서 수정") { options[:in_place] = true }
        opts.on("--report", "본문 대신 JSON 보고서만 출력") { options[:report] = true }
      end
      path = parser.parse!(argv).first
      source = path ? File.read(path, encoding: "UTF-8") : $stdin.read.force_encoding(Encoding::UTF_8)
      out, report = sanitize(source)

      if options[:report]
        puts JSON.pretty_generate(report.to_h)
      elsif options[:in_place]
        raise OptionParser::MissingArgument, "--in-place 는 파일 경로가 필요합니다" unless path

        File.write(path, out, encoding: "UTF-8") if report.changed?
        puts report.summary.empty? ? "정리할 항목 없음" : report.summary
      else
        $stdout.write(out)
      end
      0
    end

    private

    def strip_invisibles(text, counts)
      text = replace_counted(text, INVISIBLE_ALWAYS, "", counts, "invisible")
      text = replace_counted(text, BIDI, "", counts, "bidi")
      text = replace_counted(text, TAG_CHARS, "", counts, "tag_chars")
      strip_joiners_outside_emoji(text, counts)
    end

    def replace_counted(text, pattern, replacement, counts, key)
      counts[key] += text.scan(pattern).size
      text.gsub(pattern, replacement)
    end

    def strip_joiners_outside_emoji(text, counts)
      return text if JOINERS.none? { |joiner| text.include?(joiner) }

      chars = text.chars
      kept = []
      chars.each_with_index do |char, index|
        if JOINERS.include?(char) && plain?(kept.last) && plain?(chars[index + 1])
          counts["invisible"] += 1
          next
        end
        kept << char
      end
      kept.join
    end

    def plain?(char) = char.nil? || char.match?(PLAIN_NEIGHBOR)

    def normalize_line_breaks(text, counts)
      counts["line_breaks"] = text.scan("\r\n").size + text.scan(/\r(?!\n)/).size + text.scan(UNI_BREAKS).size
      text = text.gsub("\r\n", "\n").tr("\r", "\n").gsub(UNI_BREAKS, "\n")
      counts["trailing_space_lines"] = text.scan(/[ \t]+$/).size
      text.gsub(/[ \t]+$/, "")
    end

    def summary(counts, changed)
      return "" unless changed

      SUMMARY_LABELS.filter_map { |key, label| format(label, counts[key]) if counts[key].positive? }.join(" · ")
    end
  end
end

exit HumanizeKoreanSanitize.main if $PROGRAM_NAME == __FILE__
