#!/usr/bin/env ruby
# typed: false
# frozen_string_literal: true
# rbs_inline: enabled

# Humanize KR v2.0 — monolith input shim.
#
# Computes quantitative metrics and prepends them to the text a monolith agent
# reads. In --chunk mode it creates lossless, deterministic chunks plus a
# manifest for reassemble_chunks.rb. This script uses Ruby's standard library
# only and deliberately degrades to an input without scores when metrics fail.

require "date"
require "digest"
require "fileutils"
require "json"
require "optparse"
require "pathname"

HERE = File.expand_path(__dir__)
PROJECT_ROOT = File.expand_path("..", HERE)
METRICS_DIR = File.expand_path("../references", HERE)

begin
  require File.join(METRICS_DIR, "metrics_v2")
  METRICS_PROVIDER = MetricsV2
rescue StandardError, LoadError
  begin
    require File.join(METRICS_DIR, "metrics")
    # @rbs skip
    METRICS_PROVIDER = HumanizeKoreanMetrics
  rescue StandardError, LoadError
    # @rbs skip
    METRICS_PROVIDER = nil
  end
end

ROUTE_LIGHT_MAX_TELLS = 2
ROUTE_HEAVY_MIN_TELLS = 8
ROUTE_HEAVY_MIN_CHARS = 15_000
ROUTE_TELL_KEYS_V16 = %w[conclusion_pivot_count safe_balance_count].freeze
ROUTE_TELL_KEYS_V2 = %w[double_passive_count by_passive_count have_make_literal_count double_particle_count].freeze

V2_COUNT_METRICS = [
  [ "double_passive_count", "이중 피동", "A-8", :integer ],
  [ "by_passive_count", "~에 의해 피동", "A-9", :integer ],
  [ "pronoun_density", "인칭 대명사 밀도", "A-16", :three_decimal ],
  [ "have_make_literal_count", "have/make 직역", "A-7", :integer ],
  [ "double_particle_count", "이중 조사 결합", "A-19", :integer ],
  [ "relative_clause_nesting", "관형절 3중+ 중첩 문장 수", "A-18", :integer ],
  [ "deul_overuse_rate", "'-들' 남용률", "A-17 hold", :three_decimal ]
].freeze

TARGET_CHUNK_CHARS = 7000
MAX_CHUNK_CHARS = 9000
SENT_SPLIT_TRIGGER_CHARS = 4000
CHUNK_RECOMMEND_MIN_CHARS = ROUTE_HEAVY_MIN_CHARS
HEADING_LINE_RE = /^(\#{1,6}\s|[ⅠⅡⅢⅣⅤⅥⅦⅧⅨⅩ]+\.|\d+\.\s|\d+\)\s|제\s*\d+\s*[장절편]|[가나다라마바사아자차카타파하]\.\s|\([0-9가-힣]+\))/
FOOTNOTE_LINE_RE = /^(?:\d+\)\s|\[\d+\]\s)/
PARA_SEP_RE = /\n{2,}/
SENT_END_RE = /[.!?。！？…]['\"”’』」)\]]*\s+/

class ChunkingError < RuntimeError; end

def next_run_dir(workspace)
  FileUtils.mkdir_p(workspace)
  today = Date.today.iso8601
  n = 1
  loop do
    candidate = File.join(workspace, format("%s-%03d", today, n))
    return candidate unless File.exist?(candidate)

    n += 1
  end
end

def resolve_run_dir(run_dir_arg, text_arg)
  if run_dir_arg
    run_dir = Pathname.new(run_dir_arg).absolute? ? run_dir_arg : File.join(PROJECT_ROOT, run_dir_arg)
    FileUtils.mkdir_p(run_dir)
    return File.expand_path(run_dir)
  end
  raise "Either --run-dir or --text is required" if text_arg.nil?

  run_dir = next_run_dir(File.join(PROJECT_ROOT, "_workspace"))
  FileUtils.mkdir_p(run_dir)
  run_dir
end

def compute_route_hint(metrics_obj)
  metrics = metrics_obj["metrics"] || {}
  v2_metrics = metrics_obj["v2_metrics"] || {}
  tells = ROUTE_TELL_KEYS_V16.sum { |key| (metrics[key] || 0).to_i } +
    ROUTE_TELL_KEYS_V2.sum { |key| (v2_metrics[key] || 0).to_i }
  chars = (metrics_obj["char_count"] || 0).to_i
  risk = metrics_obj.fetch("risk_band", "unknown")

  if chars > ROUTE_HEAVY_MIN_CHARS
    hint = "heavy"
    reason = "#{chars.to_s.reverse.gsub(/(...)(?=.)/, '\\1,').reverse}자 초장문(>#{ROUTE_HEAVY_MIN_CHARS.to_s.reverse.gsub(/(...)(?=.)/, '\\1,').reverse}) — 진단 + 청킹 권장"
  elsif risk == "high" && tells >= ROUTE_HEAVY_MIN_TELLS
    hint = "heavy"
    reason = "risk_band high + 카운트형 티 #{tells}건 — AI 슬롭 밀집, 진단 + 청킹 권장"
  elsif tells <= ROUTE_LIGHT_MAX_TELLS && %w[low medium].include?(risk)
    hint = "light"
    reason = "카운트형 어휘·피동 티 #{tells}건 · risk_band #{risk} — 이미 잘 쓴 글, 단일 콜·최소 파이프라인 권장"
  else
    hint = "standard"
    reason = "카운트형 티 #{tells}건 · risk_band #{risk} — 진단 + 단일 윤문 권장"
  end

  {
    "route_hint" => hint,
    "route_reason" => reason,
    "route_signals" => { "lexical_tell_count" => tells, "risk_band" => risk, "char_count" => chars }
  }
end

def fmt_z(value)
  return "n/a" if value.nil?

  value = value.to_f
  format("z=%s%.2f", value >= 0 ? "+" : "", value)
end

def z_marker(value)
  return "" if value.nil?

  return "  ★ S1 트리거" if value.to_f >= 1.5
  return "  · S2 시그널" if value.to_f >= 1.0

  ""
end

def python_repr(value)
  "'#{value.to_s.gsub("\\", "\\\\").gsub("'", "\\'")}'"
end

def render_v2_counts(metrics_obj)
  v2_metrics = metrics_obj["v2_metrics"]
  return [] unless v2_metrics

  lines = [ "[v2.0 카운트형 지표 — 원값 / baseline calibration 전 z-score 해석 보류]" ]
  V2_COUNT_METRICS.each do |key, label, tell_id, kind|
    value = v2_metrics[key]
    if value.nil?
      lines << "- #{key}: n/a"
      next
    end
    rendered = kind == :integer ? value.to_i.to_s : format("%.3f", value.to_f)
    lines << "- #{key} (#{label}, 본진 #{tell_id}): #{rendered}"
  end
  lines << "- 카운트 > 0 지표는 해당 본진 ID 처방(quick-rules.md·taxonomy)과 교차 확인 후 윤문할 것."
  lines << ""
end

# rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
# Rendering is deliberately linear to preserve the Python shim's exact block order.
def render_block(metrics_obj)
  metrics = metrics_obj["metrics"] || {}
  z_scores = metrics_obj["z_scores"] || {}
  evidence = metrics_obj["evidence"] || {}
  pivots = evidence["conclusion_pivots"] || []
  safe_balances = evidence["safe_balances"] || []
  genre = metrics_obj.fetch("genre", "essay")

  row = lambda do |key, value_format, with_z: true, suffix: ""|
    value = metrics[key]
    next "- #{key}: n/a" if value.nil?

    z_part = with_z ? "  (#{fmt_z(z_scores[key])} vs #{genre} 인간 baseline)#{z_marker(z_scores[key])}" : ""
    "- #{key}: #{format(value_format, value)}#{z_part}#{suffix}"
  end

  lines = []
  lines << "[정량 사전 점수 v2.0 — v1.6 8지표(KatFish baseline) + v2.0 카운트형]"
  lines << "risk_band: #{metrics_obj.fetch("risk_band", "unknown")}  (score #{metrics_obj.fetch("risk_score", 0)})"
  if metrics_obj["route_hint"]
    lines << "route_hint: #{metrics_obj["route_hint"]}  (권고 — 사용자·오케스트레이터가 무시 가능)"
    lines << "route_reason: #{metrics_obj.fetch("route_reason", "")}"
  end
  lines << "genre: #{genre}"
  lines << "char_count: #{metrics_obj.fetch("char_count", 0)}"
  lines << "warning: #{metrics_obj["warning"]}" if metrics_obj["warning"]
  lines << ""
  lines << "[v1.6 지표]"
  lines << row.call("comma_inclusion_rate", "%.2f")
  lines << row.call("comma_usage_rate", "%.2f")
  lines << row.call("ending_comma_rate", "%.2f")
  lines << row.call("comma_segment_length", "%.2f")
  pivot_suffix = pivots.empty? ? "" : "  (lexicon 매치: #{pivots.map { |item| python_repr(item) }.join(", ")})"
  lines << "- conclusion_pivot_count: #{(metrics["conclusion_pivot_count"] || 0).to_i}#{pivot_suffix}"
  safe_suffix = safe_balances.empty? ? "" : "  (lexicon 매치: #{safe_balances.map { |item| python_repr(item) }.join(", ")})"
  lines << "- safe_balance_count: #{(metrics["safe_balance_count"] || 0).to_i}#{safe_suffix}"
  lines << row.call("hanja_nominalizer_density", "%.3f")
  lines << row.call("lexical_diversity", "%.2f")
  lines << ""
  lines.concat(render_v2_counts(metrics_obj))
  lines << "[근거 사용 가이드]"
  lines << "- 위 점수는 *근거 보조*다. 단독 판정 금지(보고서 명시)."
  lines << "- z>1.0 지표는 quick-rules.md S1·S2 패턴과 교차 확인 후 윤문할 것."
  lines << "- ending_comma_rate가 ★ S1 트리거인 경우 C-11(연결어미 뒤 쉼표) 우선 손질."
  lines << "- conclusion_pivot 매치 토큰은 D-1·H-1 처방 적용 대상."
  lines << ""
  lines.join("\n")
end
# rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

def render_combined(text, metrics_obj, diagnosis = nil)
  parts = []
  if diagnosis
    parts << "[진단]"
    parts << diagnosis.sub(/\n+\z/, "")
    parts << "[진단 끝]"
    parts << ""
  end
  parts << render_block(metrics_obj) if metrics_obj
  parts << "[원문 시작]"
  parts << text.sub(/\n+\z/, "")
  parts << "[원문 끝]"
  parts << ""
  parts.join("\n")
end

def line_spans(text)
  spans = []
  position = 0
  while position < text.length
    newline = text.index("\n", position)
    if newline.nil?
      spans << [ position, text.length ]
      break
    end
    spans << [ position, newline + 1 ]
    position = newline + 1
  end
  spans
end

def find_footnote_block_start(text)
  start = nil
  line_spans(text).reverse_each do |line_start, line_end|
    line = text[line_start...line_end]
    next if line.strip.empty?
    if FOOTNOTE_LINE_RE.match?(line)
      start = line_start
    else
      break
    end
  end
  start
end

def has_substantive?(body, start_pos, end_pos)
  body[start_pos...end_pos].each_line.any? { |line| !line.strip.empty? && !HEADING_LINE_RE.match?(line) }
end

def ends_with_heading?(body, start_pos, end_pos)
  region = body[start_pos...end_pos].sub(/\s+\z/, "")
  return false if region.empty?

  HEADING_LINE_RE.match?(region.rpartition("\n").last)
end

def sentence_pieces(text, start_pos, end_pos, target)
  segment = text[start_pos...end_pos]
  bounds = []
  segment.to_enum(:scan, SENT_END_RE).each do
    m = Regexp.last_match
    next unless m

    bounds << start_pos + m.end(0) if start_pos + m.end(0) < end_pos
  end
  pieces = []
  piece_start = start_pos
  previous = nil
  bounds.each do |bound|
    if bound - piece_start > target
      cut = previous && previous > piece_start ? previous : bound
      pieces << [ piece_start, cut ]
      piece_start = cut
      previous = bound > cut ? bound : nil
    else
      previous = bound
    end
  end
  if end_pos - piece_start > target && previous && previous > piece_start
    pieces << [ piece_start, previous ]
    piece_start = previous
  end
  pieces << [ piece_start, end_pos ]
end

# rubocop:disable Metrics/PerceivedComplexity
# Greedy packing is kept in one method to preserve offset and lossless invariants.
def pack_segment(body, segment_start, segment_end, target, _max_chunk, warnings)
  units = []
  position = segment_start
  body[segment_start...segment_end].to_enum(:scan, PARA_SEP_RE).each do
    m = Regexp.last_match
    next unless m

    match_end = segment_start + m.end(0)
    break if match_end >= segment_end

    units << [ position, match_end ]
    position = match_end
  end
  units << [ position, segment_end ] if position < segment_end

  pieces = units.flat_map do |unit_start, unit_end|
    if unit_end - unit_start > SENT_SPLIT_TRIGGER_CHARS
      sentence_pieces(body, unit_start, unit_end, target).tap do |subpieces|
        subpieces.each do |sub_start, sub_end|
          segment = body[sub_start...sub_end]
          if sub_end - sub_start > SENT_SPLIT_TRIGGER_CHARS && !SENT_END_RE.match?(segment)
            warnings << "문장 경계로 쪼갤 수 없는 초장 구간 #{sub_end - sub_start}자 (offset #{sub_start}) — 경고 기준(#{SENT_SPLIT_TRIGGER_CHARS}) 초과 허용, 검토 요망"
          end
        end
      end
    else
      [ [ unit_start, unit_end ] ]
    end
  end

  chunks = []
  current_start = nil
  current_end = 0
  pieces.each do |piece_start, piece_end|
    if current_start.nil?
      current_start = piece_start
      current_end = piece_end
      next
    end
    would = (current_end - current_start) + (piece_end - piece_start)
    if would > target && !ends_with_heading?(body, current_start, current_end)
      chunks << [ current_start, current_end ]
      current_start = piece_start
      current_end = piece_end
    else
      current_end = piece_end
    end
  end
  chunks << [ current_start, current_end ] if current_start
  chunks
end
# rubocop:enable Metrics/PerceivedComplexity

# rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
# This is the lossless chunking invariant boundary; branches mirror the Python source.
def compute_chunk_spans(text, target: TARGET_CHUNK_CHARS, max_chunk: MAX_CHUNK_CHARS)
  warnings = []
  return [ [], warnings ] if text.empty?

  footnote_start = find_footnote_block_start(text)
  body_end = footnote_start || text.length
  spans = []
  if body_end.positive?
    body = text[0...body_end]
    cuts = [ 0 ]
    line_spans(body).each do |line_start, line_end|
      next if line_start.zero?
      cuts << line_start if HEADING_LINE_RE.match?(body[line_start...line_end]) && has_substantive?(body, cuts.last, line_start)
    end
    cuts << body_end
    cuts.each_cons(2) do |segment_start, segment_end|
      pack_segment(body, segment_start, segment_end, target, max_chunk, warnings).each do |chunk_start, chunk_end|
        spans << { "start" => chunk_start, "end" => chunk_end, "passthrough" => false }
      end
    end
  end
  spans << { "start" => footnote_start, "end" => text.length, "passthrough" => true } if footnote_start

  spans.each_with_index do |span, index|
    size = span["end"] - span["start"]
    warnings << "청크 #{index + 1} 크기 #{size}자 — 상한(#{max_chunk}) 초과" if !span["passthrough"] && size > max_chunk
    if !span["passthrough"] && ends_with_heading?(text, span["start"], span["end"])
      warnings << "청크 #{index + 1}가 헤딩으로 끝남 — 뒤따르는 본문이 없는 문서 말미 헤딩"
    end
  end

  joined = spans.map { |span| text[span["start"]...span["end"]] }.join
  raise ChunkingError, "lossless self-check failed: 청크 연결 결과가 원문과 불일치 (원문 #{text.length}자, 연결 #{joined.length}자)" unless joined == text

  [ spans, warnings ]
end
# rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

def render_chunk_header(index, total, starts_with_heading)
  lines = [
    "[청크 컨텍스트] 이 텍스트는 한 문서를 나눈 청크 #{index}/#{total}이다.",
    "- 문서 전체가 아니므로 서두·결말·전환 문구를 새로 만들지 말 것. 경계가 잘린 듯 보여도 그대로 둔다."
  ]
  lines << "- 첫 줄은 제목/헤딩이다. 번호·기호·형식을 그대로 보존하고 본문 문장과 병합하지 말 것." if starts_with_heading
  lines << ""
  lines.join("\n")
end

def compute_metrics(text, options)
  return nil unless METRICS_PROVIDER

  METRICS_PROVIDER.compute_all(text, genre: options[:genre], baseline_path: options[:baseline])
end

def error_details(error)
  "metrics_failed: #{error.class}: #{error.message}\n\n#{error.full_message}"
end

# rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
# Chunk setup, stale cleanup, and manifest emission must remain one ordered operation.
def run_chunk_mode(options, diagnosis)
  run_dir = resolve_run_dir(options[:run_dir], options[:text])
  input_path = File.join(run_dir, "01_input.txt")
  File.write(input_path, options[:text], encoding: "UTF-8") unless options[:text].nil?
  raise "01_input.txt not found in #{run_dir}; pass --text to create" unless File.exist?(input_path)

  text = File.read(input_path, encoding: "UTF-8")
  raise "01_input.txt is empty; nothing to chunk" if text.strip.empty?

  spans, warnings = compute_chunk_spans(text)
  route = nil
  if METRICS_PROVIDER
    begin
      route = compute_route_hint(compute_metrics(text, options))
    rescue StandardError
      route = nil
    end
  end
  if text.length <= CHUNK_RECOMMEND_MIN_CHARS
    warnings << "입력 #{text.length.to_s.reverse.gsub(/(...)(?=.)/, '\\1,').reverse}자 ≤ 청킹 권장 최소 #{CHUNK_RECOMMEND_MIN_CHARS.to_s.reverse.gsub(/(...)(?=.)/, '\\1,').reverse}자 — 단일 콜 실증 범위라 --chunk 비권장 (권고, route_hint 참조)"
  end

  removed = []
  [ "00_chunk_*", "01_chunk_*", "02_chunk_*_rewritten.txt", "03_reassembled.md", "03_reassembly_report.json" ].each do |pattern|
    Dir.glob(File.join(run_dir, pattern)).sort.each do |stale|
      File.delete(stale)
      removed << File.basename(stale)
    end
  end

  total = spans.length
  entries = []
  degraded = 0
  spans.each_with_index do |span, offset|
    index = offset + 1
    chunk_text = text[span["start"]...span["end"]] || ""
    first_line = chunk_text.sub(/\A\n+/, "").split("\n", 2).first || ""
    starts_with_heading = !span["passthrough"] && HEADING_LINE_RE.match?(first_line)
    entry = {
      "index" => index, "start" => span["start"], "end" => span["end"],
      "char_count" => span["end"] - span["start"], "starts_with_heading" => starts_with_heading,
      "heading" => starts_with_heading ? first_line.strip : nil, "passthrough" => span["passthrough"],
      "input_file" => nil, "rewritten_file" => nil
    }
    unless span["passthrough"]
      entry["input_file"] = format("01_chunk_%02d_input_with_metrics.txt", index)
      entry["rewritten_file"] = format("02_chunk_%02d_rewritten.txt", index)
      metrics_obj = nil
      metrics_path = File.join(run_dir, format("00_chunk_%02d_metrics.json", index))
      error_path = File.join(run_dir, format("00_chunk_%02d_metrics.error", index))
      if METRICS_PROVIDER.nil?
        File.write(error_path, "metrics module import failed; chunk emitted without score block", encoding: "UTF-8")
        degraded += 1
      else
        begin
          metrics_obj = compute_metrics(chunk_text, options)
          File.write(metrics_path, JSON.pretty_generate(metrics_obj), encoding: "UTF-8")
        rescue StandardError => error
          metrics_obj = nil
          degraded += 1
          File.write(error_path, error_details(error), encoding: "UTF-8")
        end
      end
      combined = render_chunk_header(index, total, starts_with_heading) + render_combined(chunk_text, metrics_obj, diagnosis)
      File.write(File.join(run_dir, entry["input_file"]), combined, encoding: "UTF-8")
    end
    entries << entry
  end

  manifest = {
    "version" => 1, "created" => Date.today.iso8601, "source_file" => "01_input.txt", "source_chars" => text.length,
    "source_sha256" => Digest::SHA256.hexdigest(text.encode("UTF-8")), "genre" => options[:genre],
    "target_chunk_chars" => TARGET_CHUNK_CHARS, "max_chunk_chars" => MAX_CHUNK_CHARS,
    "route_hint" => route && route["route_hint"], "route_reason" => route && route["route_reason"],
    "chunk_count" => total, "body_chunk_count" => entries.count { |entry| !entry["passthrough"] },
    "passthrough_chunk_count" => entries.count { |entry| entry["passthrough"] }, "lossless_check" => "ok",
    "warnings" => warnings, "chunks" => entries
  }
  manifest_path = File.join(run_dir, "chunk_manifest.json")
  File.write(manifest_path, JSON.pretty_generate(manifest), encoding: "UTF-8")
  sizes = entries.map { |entry| entry["char_count"] }
  puts "run_dir=#{run_dir}\nmanifest=#{manifest_path}\nchunks=#{total} (body #{manifest["body_chunk_count"]} + passthrough #{manifest["passthrough_chunk_count"]})\nsizes=#{sizes}\nroute_hint=#{manifest["route_hint"]}\nmetrics_degraded_chunks=#{degraded}\nstale_removed=#{removed.length}\nwarnings=#{warnings.length}"
  warnings.each { |warning| puts "WARNING: #{warning}" }
  0
end
# rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

def parse_options(argv)
  options = { genre: "essay", baseline: nil, diagnosis: nil, chunk: false }
  parser = OptionParser.new do |opts|
    opts.banner = "Usage: prepare_monolith_input.rb (--run-dir DIR | --text TEXT) [options]"
    opts.on("--run-dir DIR", "Existing run directory (relative ok)") { |value| options[:run_dir] = value }
    opts.on("--text TEXT", "Inline text input (creates new run dir)") { |value| options[:text] = value }
    opts.on("--genre GENRE", "Genre hint (default: essay)") { |value| options[:genre] = value }
    opts.on("--baseline PATH", "Override baseline JSON path (default: project default)") { |value| options[:baseline] = value }
    opts.on("--diagnosis PATH", "Path to a diagnosis text file; prepended before the metrics block") { |value| options[:diagnosis] = value }
    opts.on("--chunk", "장문 청킹 모드") { options[:chunk] = true }
  end
  parser.parse!(argv)
  options
end

def main(argv = ARGV)
  options = parse_options(argv)
  diagnosis = nil
  if options[:diagnosis]
    diagnosis_path = Pathname.new(options[:diagnosis]).absolute? ? options[:diagnosis] : File.join(PROJECT_ROOT, options[:diagnosis])
    raise "--diagnosis file not found: #{diagnosis_path}" unless File.exist?(diagnosis_path)

    diagnosis = File.read(diagnosis_path, encoding: "UTF-8")
  end
  return run_chunk_mode(options, diagnosis) if options[:chunk]

  run_dir = resolve_run_dir(options[:run_dir], options[:text])
  input_path = File.join(run_dir, "01_input.txt")
  File.write(input_path, options[:text], encoding: "UTF-8") unless options[:text].nil?
  raise "01_input.txt not found in #{run_dir}; pass --text to create" unless File.exist?(input_path)

  text = File.read(input_path, encoding: "UTF-8")
  metrics_obj = nil
  metrics_path = File.join(run_dir, "00_metrics.json")
  error_path = File.join(run_dir, "00_metrics.error")
  if METRICS_PROVIDER.nil?
    File.write(error_path, "metrics module import failed; combined file emitted without score block", encoding: "UTF-8")
  else
    begin
      metrics_obj = compute_metrics(text, options)
      metrics_obj.merge!(compute_route_hint(metrics_obj))
      File.write(metrics_path, JSON.pretty_generate(metrics_obj), encoding: "UTF-8")
      File.delete(error_path) if File.exist?(error_path)
    rescue StandardError => error
      metrics_obj = nil
      File.write(error_path, error_details(error), encoding: "UTF-8")
    end
  end
  combined_path = File.join(run_dir, "01_input_with_metrics.txt")
  File.write(combined_path, render_combined(text, metrics_obj, diagnosis), encoding: "UTF-8")
  puts "run_dir=#{run_dir}\ncombined=#{combined_path}\nrisk_band=#{metrics_obj ? metrics_obj.fetch("risk_band", "absent") : "absent"}  risk_score=#{metrics_obj ? metrics_obj.fetch("risk_score", "absent") : "absent"}\nroute_hint=#{metrics_obj ? metrics_obj.fetch("route_hint", "absent") : "absent"}\ndegraded=#{metrics_obj.nil?}"
  0
rescue OptionParser::ParseError, RuntimeError, Errno::ENOENT => error
  warn error.message
  1
end

exit(main) if $PROGRAM_NAME == __FILE__
