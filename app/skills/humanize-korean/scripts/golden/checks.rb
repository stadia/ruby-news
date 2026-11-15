#!/usr/bin/env ruby
# typed: false
# frozen_string_literal: true
# rbs_inline: enabled

# Deterministic golden-fixture scorer for humanize-korean.
# Standard library only. Failure codes and messages are a stable API.

# rubocop:disable Metrics/ModuleLength
module HumanizeKoreanGoldenChecks
  # 멤버 타입: sorbet/rbi/shims/data_definitions.rbi
  Failure = Data.define(:code, :message)

  class Failure
    #: () -> String
    def to_s = "[#{code}] #{message}"
  end

  HAYEOT_RE = /하였/
  CLICHE_PATTERNS = [
    [ "기록적인 성과", /기록적인\s*성과/ ],
    [ "괄목할 만한", /괄목할\s*만한/ ],
    [ "~로 평가된다", /로\s*평가(?:된다|받|되)/ ],
    [ "주목받-", /주목받/ ],
    [ "크게 기여", /크게\s*기여/ ],
    [ "중요한 역할을 한다", /중요한\s*역할을\s*(?:한다|했다|할)/ ],
    [ "시사하는 바가 크다", /시사하는\s*바가\s*크/ ],
    [ "의미가 크다", /의미가\s*크다/ ]
  ].freeze
  YO_ENDING_RE = /요\s*(?:[.?!…]|$)/
  MIN_YO = 3
  KEEP_RATIO = 0.5

  HEADING_PREFIX = /^(?:\#{1,6}\s+|[ⅠⅡⅢⅣⅤⅥⅦⅧⅨⅩⅪⅫ]+\.\s*|\d{1,2}\.\s+|\(\d{1,2}\)\s*|제\d+[장절]\s*)/
  PROSE_ENDING = /(?:다|요|음|함|까)\s*[.?!]$/
  DEF_LINE = /^\s*\d{1,3}\)\s/
  INLINE_MARKER = /(?<=\S)(?<![(\d])(\d{1,3})\)/
  DEF_LABEL = /(?:^|(?<=\s))(\d{1,3})\)\s/
  NUM_TOKEN = /\d+(?:[.,]\d+)*/
  ANCHOR_WINDOW = 50

  KO_UNIT_MULT = {
    "백" => 100, "천" => 1_000, "만" => 10_000,
    "억" => 100_000_000, "조" => 1_000_000_000_000
  }.freeze
  MIN_QUOTE_LEN = 8
  SUMMARY_BLOCK_RE = /<!--\s*HUMANIZE-SUMMARY\b.*/m

  class << self
    def normalize_whitespace(text) = text.gsub(/\s+/, " ").strip

    def check_register(original, output)
      failures = []
      before_count = original.scan(HAYEOT_RE).length
      after_count = output.scan(HAYEOT_RE).length
      if after_count > before_count
        failures << Failure.new("hayeot_injection", "'하였' 계열이 원문 #{before_count}회 → 윤문본 #{after_count}회로 늘었습니다 (격식 상향 주입)")
      end

      CLICHE_PATTERNS.each do |name, pattern|
        before_count = original.scan(pattern).length
        after_count = output.scan(pattern).length
        if after_count > before_count
          failures << Failure.new("cliche_injection", "상투구 '#{name}'이 원문 #{before_count}회 → 윤문본 #{after_count}회로 늘었습니다 (주입 금지)")
        end
      end

      before_count = original.scan(YO_ENDING_RE).length
      after_count = output.scan(YO_ENDING_RE).length
      if before_count >= MIN_YO && after_count < before_count * KEEP_RATIO
        failures << Failure.new("colloquial_erased", "구어 종결(~요)이 원문 #{before_count}회 → 윤문본 #{after_count}회로 격감했습니다 (격식 역주행; register는 Before/After 동일이 철칙)")
      end
      failures
    end

    def extract_headings(text)
      text.lines.filter_map do |line|
        stripped = line.strip
        next if stripped.empty? || stripped.length > 50 || DEF_LINE.match?(stripped)
        next unless HEADING_PREFIX.match?(stripped)
        next if PROSE_ENDING.match?(stripped)

        core = stripped.sub(HEADING_PREFIX, "").strip
        next if core.empty?

        [ normalize_whitespace(stripped), core ]
      end
    end

    def check_headings(original, output)
      failures = []
      output_lines = output.lines.map(&:strip).reject(&:empty?).map { |line| normalize_whitespace(line) }.to_h { |line| [ line, true ] }
      output_joined = normalize_whitespace(output)
      extract_headings(original).each do |line, core|
        next if output_lines.key?(line)

        if output_joined.include?(core)
          failures << Failure.new("heading_absorbed", "제목 '#{line}'이 독립 줄에서 사라지고 본문에 흡수됐습니다")
        else
          failures << Failure.new("heading_lost", "제목 '#{line}'이 윤문본에서 사라졌습니다")
        end
      end
      failures
    end

    # Annotated so `line` below is a String: with `text` untyped, `line.length`
    # is untyped too and `offset + untyped` resolves against every `Integer#+`
    # overload, widening the offset accumulator to BigDecimal.
    #: (String) -> Array[untyped]
    def extract_inline_markers(text)
      markers = []
      offset = 0
      text.each_line do |line|
        unless DEF_LINE.match?(line)
          line.to_enum(:scan, INLINE_MARKER).each do
            match = Regexp.last_match
            next unless match

            markers << [ match[1], offset + match.begin(1) ]
          end
        end
        offset += line.length
      end
      markers
    end

    def extract_defs(text)
      text.lines.each_with_object({}) do |line, definitions|
        next unless DEF_LINE.match?(line)

        labels = []
        line.to_enum(:scan, DEF_LABEL).each do
          match = Regexp.last_match
          next unless match

          labels << [ match.begin(0), match[1] ]
        end
        labels.each_with_index do |(position, number), index|
          ending = labels[index + 1]&.first || line.length
          content = line[position...ending].sub(/^\s*\d{1,3}\)\s*/, "")
          definitions[number] = normalize_whitespace(content)
        end
      end
    end

    def nearest_num_before(text, position)
      segment = text[[ position - ANCHOR_WINDOW, 0 ].max...position]
      segment.scan(NUM_TOKEN).last
    end

    # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    def check_footnotes(original, output)
      failures = []
      input_markers = extract_inline_markers(original)
      output_markers = extract_inline_markers(output)
      return failures if input_markers.empty? && extract_defs(original).empty?

      if output_markers.length < input_markers.length
        failures << Failure.new("footnote_count", "본문 각주 표시가 #{input_markers.length}개 → #{output_markers.length}개로 줄었습니다")
      end

      input_numbers = input_markers.map(&:first).uniq
      output_numbers = output_markers.map(&:first).uniq
      if input_numbers.sort_by(&:to_i) != output_numbers.sort_by(&:to_i)
        missing = (input_numbers - output_numbers).sort_by(&:to_i)
        invented = (output_numbers - input_numbers).sort_by(&:to_i)
        parts = []
        parts << "소실 #{python_list(missing)}" unless missing.empty?
        parts << "신규 #{python_list(invented)}" unless invented.empty?
        failures << Failure.new("footnote_numbers", "각주 번호 집합이 달라졌습니다: #{parts.join(', ')}")
      end

      output_first_positions = output_markers.each_with_object({}) { |(number, position), hash| hash[number] ||= position }
      input_markers.each do |number, position|
        anchor = nearest_num_before(original, position)
        next if anchor.nil? || !output_first_positions.key?(number)

        output_anchor = nearest_num_before(output, output_first_positions.fetch(number))
        if output_anchor != anchor
          failures << Failure.new("footnote_anchor", "각주 #{number})이 원위치를 벗어났습니다 (인접 수치 앵커 '#{anchor}' → '#{python_value(output_anchor)}'): 인용 출처 변조 위험")
        end
      end

      extract_defs(original).each do |number, content|
        output_definition = extract_defs(output)[number]
        if output_definition.nil?
          failures << Failure.new("footnote_def", "각주 정의 #{number})이 윤문본에서 사라졌습니다")
        elsif output_definition != content
          failures << Failure.new("footnote_def", "각주 정의 #{number})의 내용이 달라졌습니다 (서지사항은 불변이어야 함)")
        end
      end
      failures
    end
    # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

    def number_values(text)
      values = {}
      text.scan(NUM_TOKEN) do |matched_token|
        m = Regexp.last_match
        next unless m

        token = matched_token.delete(",")
        unit = text[m.end(0), 1]
        multiplier = KO_UNIT_MULT[unit]
        if multiplier
          begin
            value = Float(token) * multiplier
            values[(value == value.to_i ? value.to_i : value).to_s] = true
          rescue ArgumentError
            values[token] = true
          end
        else
          values[token] = true
        end
      end
      values.keys
    end

    def python_list(values)
      "[#{values.map { |value| "'#{value}'" }.join(', ')}]"
    end

    def python_value(value) = value.nil? ? "None" : value

    def dropped_numbers(original, output)
      (number_values(original) - number_values(output)).sort
    end

    def check_numbers(original, output)
      injected = (number_values(output) - number_values(original)).sort
      return [] if injected.empty?

      [ Failure.new("number_injected", "원문에 없던 수치가 윤문본에 등장했습니다: #{python_list(injected)} (수치 불변 철칙 — 없던 주장 주입 위험)") ]
    end

    def extract_quotes(text, min_len: MIN_QUOTE_LEN)
      quotes = [ [ "「", "」" ], [ "『", "』" ], [ "“", "”" ] ].flat_map do |open, close|
        text.scan(/#{Regexp.escape(open)}([^#{Regexp.escape(close)}]+)#{Regexp.escape(close)}/).flatten
      end
      parts = text.split('"')
      quotes.concat(parts.each_with_index.filter_map { |part, index| part if index.odd? }) if parts.length.odd?
      quotes.select { |quote| quote.strip.length >= min_len }
    end

    def check_quotes(original, output)
      extract_quotes(original).filter_map do |quote|
        next if output.include?(quote)

        Failure.new("quote_altered", "직접 인용 「#{quote[0, 30]}…」이 윤문본에 원문 그대로 없습니다 (인용 불변 철칙)")
      end
    end

    def strip_summary_block(text) = text.sub(SUMMARY_BLOCK_RE, "").strip

    def run_checks(original, output)
      original = strip_summary_block(original)
      output = strip_summary_block(output)
      return [ Failure.new("empty_output", "윤문본이 비어 있습니다") ] if output.strip.empty?

      check_register(original, output) + check_headings(original, output) +
        check_footnotes(original, output) + check_quotes(original, output) + check_numbers(original, output)
    end

    def main(argv = ARGV)
      unless argv.length == 2
        warn "usage: ruby checks.rb <original.txt> <rewritten.txt>"
        return 2
      end

      failures = run_checks(File.read(argv[0], encoding: "UTF-8"), File.read(argv[1], encoding: "UTF-8"))
      if failures.any?
        failures.each { |failure| puts "FAIL #{failure}" }
        return 1
      end

      puts "PASS (알려진 실패 모드 없음)"
      0
    end
  end
end
# rubocop:enable Metrics/ModuleLength

exit HumanizeKoreanGoldenChecks.main if $PROGRAM_NAME == __FILE__
