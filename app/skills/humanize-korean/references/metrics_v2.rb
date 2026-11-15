# typed: false
# frozen_string_literal: true
# rbs_inline: enabled

# Humanize KR v2.0 quantitative metrics calculator.
#
# Extends the v1.6 Ruby port in metrics.rb with post-editese and
# translation-interference signals. This file intentionally uses only Ruby's
# standard library.

require "json"
require "optparse"
require "fileutils"
require_relative "metrics"

# rubocop:disable Metrics/ModuleLength, Metrics/ClassLength
module MetricsV2
  VERSION = "v2.0"
  CHANGE_RATE_WARN = 0.30
  CHANGE_RATE_ABORT = 0.50

  HANJA_SUFFIXES_V2 = %w[성 적 화 도 력 감 원].freeze
  DECLARATIVE_ENDINGS = %w[한다 된다 이다].freeze
  PROGRESSIVE_RE = /고\s*있(?:다|었|는|을|던|는다)/
  DOUBLE_PASSIVE_TOKENS = %w[
    되어진다 되어졌다 되어진 되어지는 여지다 여진다 여졌다 여진
    잊혀진 잊혀졌 잊혀진다 보여진다 보여졌다 보여진 쓰여진다 쓰여졌다
    쓰여진 닫혀진 열려진 불려진 놓여진
  ].freeze
  BY_PASSIVE_RE = /에\s*의(?:해|하여)\s+\S{0,12}?(?:되|받|당하|지)(?:다|었|어|ㄴ다|는다|는|ㄹ|을)/
  PRONOUN_RE = /(?:그녀(?:는|가|를|의|에게|와|도|만)?|그것(?:은|이|을|의|에|에게)?|그들(?:은|이|을|의|에게|과|도)?|그(?:는|가|를|의|에게|와|도|만)(?=\s|[\.,!?]|$))/
  INANIMATE_DEUL_TOKENS = %w[
    데이터들 정보들 결과들 연구들 아이디어들 방법들 문제들 의견들 시스템들 기술들
    사실들 사례들 이론들 개념들 현상들 특징들 요소들 원인들 영향들 변화들 기능들
    조건들 기준들 관점들 원리들
  ].freeze
  HAVE_MAKE_LITERAL_TOKENS = [
    "가지고 있다", "가지고있다", "가지고 있는", "가지고있는", "가지고 있었",
    "가지고있었", "가지고 있으", "가지고있으", "갖고 있다", "갖고있다",
    "갖고 있는", "갖고있는", "을 가지다", "를 가지다", "을 가졌", "를 가졌",
    "을 가진다", "를 가진다", "을 만들다", "를 만들다", "을 만들었", "를 만들었",
    "을 만들어 낸", "를 만들어 낸", "을 만들어낸", "를 만들어낸", "회의를 가지",
    "회의를 가졌", "한번 봄을 가지", "결정을 내리", "결정을 내렸"
  ].freeze
  DOUBLE_PARTICLE_RE = /(?:에서의|에로의|으로의|에의|으로부터의|로부터의)/
  PARAGRAPH_SPLIT_RE = /\n\s*\n/
  ENDING_FINAL_RE = /([가-힣]{2})[.!?]\s*$/
  ENDING_FINAL_FALLBACK_RE = /([가-힣])[.!?]\s*$/
  ANTITHESIS_RE = /(?:가|이)\s*아니라|이기\s*이전에|되기\s*이전에|이기보다/
  MARKUP_ONLY_LINE_RE = /^\s*(?:```.*|~~~.*|-{3,}|\*{3,}|={3,}|\|[\s:\-|]*)\s*$/
  MARKUP_PREFIX_RE = /^\s*(?:\#{1,6}\s+|>\s?|[-*+]\s+|\d{1,3}[.)]\s+)/

  INANIMATE_SUBJECTS = %w[
    연구 데이터 분석 결과 시스템 기술 사례 현상 이론 정책 보고서 AI 인공지능 모델
    알고리즘 변화 위기 혁신 사회 경제
  ].freeze
  UNIVERSAL_VERBS = %w[
    보여준다 보여줬다 보여주는 시사한다 시사하는 만든다 만들어 드러낸다 드러냈다
    드러내는 제시한다 제시했다 나타낸다 나타냈다 나타내는 증명한다 증명했다 말해준다
    말해주는 의미한다 의미하는 가져온다 가져왔다 가져오는
  ].freeze
  CONTENT_STOPWORDS = %w[
    그리고 그러나 하지만 또한 또는 혹은 즉 예를 예컨대 이는 이것은 그것은 그러므로 따라서
  ].freeze
  CONTENT_ENDINGS = %w[한다 된다 이다 했다 였다 었다 답다 스럽다 롭다 하다 되다].freeze

  class << self
    # v1.6 functions remain delegated to metrics.rb rather than reimplemented.
    def comma_inclusion_rate(text) = v1_call(:comma_inclusion_rate, text)
    def comma_usage_rate(text) = v1_call(:comma_usage_rate, text)
    def ending_comma_rate(text) = v1_call(:ending_comma_rate, text)
    def comma_segment_length(text) = v1_call(:comma_segment_length, text)
    def conclusion_pivot_count(text, lexicon = nil)
      lexicon.nil? ? v1_call(:conclusion_pivot_count, text) : v1_call(:conclusion_pivot_count, text, lexicon)
    end
    def safe_balance_count(text, lexicon = nil)
      lexicon.nil? ? v1_call(:safe_balance_count, text) : v1_call(:safe_balance_count, text, lexicon)
    end
    def hanja_nominalizer_density(text) = v1_call(:hanja_nominalizer_density, text)
    def lexical_diversity(text) = v1_call(:lexical_diversity, text)

    def lexical_diversity_ttr(text)
      v1_call(:lexical_diversity, text)
    end

    def lexical_density(text)
      tokens = all_tokens(text)
      return 0.0 if tokens.empty?

      hits = tokens.count do |token|
        token.length >= 2 && !CONTENT_STOPWORDS.include?(token) &&
          (HANJA_SUFFIXES_V2.include?(token[-1]) || CONTENT_ENDINGS.any? { |ending| token.end_with?(ending) })
      end
      hits.to_f / tokens.length
    end

    def ending_diversity(text)
      keys = split_sentences(text).filter_map do |sentence|
        sentence[ENDING_FINAL_RE, 1] || sentence[ENDING_FINAL_FALLBACK_RE, 1]
      end
      return 0.0 if keys.empty?

      keys.uniq.length.to_f / keys.length
    end

    def normalisation_score(text)
      sentences = split_sentences(text)
      return 0.0 if sentences.empty?

      hits = sentences.count { |sentence| DECLARATIVE_ENDINGS.any? { |ending| last_eojeol(sentence).end_with?(ending) } }
      hits.to_f / sentences.length
    end

    def da_streak_rate(text)
      streaks = 0
      current = 0
      split_sentences(text).each do |sentence|
        if last_eojeol(sentence).end_with?("다")
          current += 1
        else
          streaks += 1 if current >= 4
          current = 0
        end
      end
      streaks += 1 if current >= 4
      streaks
    end

    def inanimate_subject_rate(text)
      sentences = split_sentences(text)
      return 0.0 if sentences.empty?

      hits = sentences.count do |sentence|
        tokens = all_tokens(sentence)
        next false if tokens.empty?

        stem = tokens.first.sub(/(?:은|는|이|가|도)\z/, "")
        inanimate = INANIMATE_SUBJECTS.include?(stem) ||
          (stem.length >= 2 && HANJA_SUFFIXES_V2.include?(stem[-1]))
        inanimate && tokens.drop(1).any? { |token| UNIVERSAL_VERBS.any? { |verb| token.include?(verb) } }
      end
      hits.to_f / sentences.length
    end

    def by_passive_count(text)
      return 0 if text.strip.empty?

      text.scan(BY_PASSIVE_RE).length
    end

    def double_passive_count(text)
      return 0 if text.strip.empty?

      DOUBLE_PASSIVE_TOKENS.sum { |token| text.scan(Regexp.new(Regexp.escape(token))).length }
    end

    def pronoun_density(text)
      densities = split_paragraphs(text).filter_map do |paragraph|
        tokens = all_tokens(paragraph)
        next if tokens.empty?

        paragraph.scan(PRONOUN_RE).length.to_f / tokens.length
      end
      return 0.0 if densities.empty?

      densities.sum / densities.length
    end

    def deul_overuse_rate(text)
      tokens = all_tokens(text)
      return 0.0 if tokens.empty?

      hits = tokens.count do |token|
        INANIMATE_DEUL_TOKENS.any? do |base|
          next true if token == base

          tail = token.delete_prefix(base)
          token.start_with?(base) && [ 1, 2 ].include?(tail.length) && tail.match?(/\A[가-힣]+\z/)
        end
      end
      hits.to_f / tokens.length
    end

    def relative_clause_nesting(text)
      adnominal_re = /[가-힣]+(?:ㄴ|는|ㄹ|던|한|된|할|될|온|간)\s+[가-힣]/
      split_sentences(text).count { |sentence| sentence.scan(adnominal_re).length >= 3 }
    end

    def have_make_literal_count(text)
      return 0 if text.strip.empty?

      HAVE_MAKE_LITERAL_TOKENS.sum { |token| text.scan(Regexp.new(Regexp.escape(token))).length }
    end

    def double_particle_count(text)
      return 0 if text.strip.empty?

      text.scan(DOUBLE_PARTICLE_RE).length
    end

    def progressive_aspect_rate(text)
      sentences = split_sentences(text)
      return 0.0 if sentences.empty?

      sentences.sum { |sentence| sentence.scan(PROGRESSIVE_RE).length }.to_f / sentences.length
    end

    def interference_index(text)
      n_sentences = [ split_sentences(text).length, 1 ].max
      n_chars = [ text.length, 1 ].max
      components = {
        "T1_inanimate_subject_rate" => inanimate_subject_rate(text),
        "T2a_by_passive_per_1k" => by_passive_count(text).to_f / n_chars * 1000,
        "T2b_double_passive_per_1k" => double_passive_count(text).to_f / n_chars * 1000,
        "T3_pronoun_density" => pronoun_density(text),
        "T4_deul_overuse_rate" => deul_overuse_rate(text),
        "T5_nested_clause_count" => relative_clause_nesting(text),
        "T6_have_make_per_1k" => have_make_literal_count(text).to_f / n_chars * 1000,
        "T7_double_particle_per_1k" => double_particle_count(text).to_f / n_chars * 1000,
        "T8b_progressive_rate" => progressive_aspect_rate(text)
      }
      weights = {
        "T1_inanimate_subject_rate" => 1.0, "T2a_by_passive_per_1k" => 0.2,
        "T2b_double_passive_per_1k" => 0.2, "T3_pronoun_density" => 4.0,
        "T4_deul_overuse_rate" => 4.0, "T5_nested_clause_count" => 0.05,
        "T6_have_make_per_1k" => 0.2, "T7_double_particle_per_1k" => 0.5,
        "T8b_progressive_rate" => 1.0
      }
      weighted_total = components.sum { |key, value| [ [ value * weights.fetch(key), 0.0 ].max, 1.0 ].min }
      { "components" => components, "weighted_total" => weighted_total, "n_sentences" => n_sentences, "n_chars" => n_chars }
    end

    def antithesis_count(text)
      return 0 if text.strip.empty?

      text.scan(ANTITHESIS_RE).length
    end

    def change_rate(before, after, ignore_markup: false)
      before = strip_markup(before) if ignore_markup
      after = strip_markup(after) if ignore_markup
      return 0.0 if before.empty? && after.empty?

      a = before.each_char.to_a
      b = after.each_char.to_a
      matches = sequence_match_size(a, b)
      1.0 - (2.0 * matches / (a.length + b.length))
    end

    def compute_all_v2(text, genre: "essay", baseline_path: nil, baseline_v2_path: nil)
      base = v1_call(:compute_all, text, genre: genre, baseline_path: baseline_path)
      metrics = {
        "lexical_diversity_ttr" => lexical_diversity_ttr(text),
        "lexical_density" => lexical_density(text),
        "ending_diversity" => ending_diversity(text),
        "normalisation_score" => normalisation_score(text),
        "da_streak_rate" => da_streak_rate(text),
        "inanimate_subject_rate" => inanimate_subject_rate(text),
        "by_passive_count" => by_passive_count(text),
        "double_passive_count" => double_passive_count(text),
        "pronoun_density" => pronoun_density(text),
        "deul_overuse_rate" => deul_overuse_rate(text),
        "relative_clause_nesting" => relative_clause_nesting(text),
        "have_make_literal_count" => have_make_literal_count(text),
        "double_particle_count" => double_particle_count(text),
        "progressive_aspect_rate" => progressive_aspect_rate(text),
        "antithesis_count" => antithesis_count(text)
      }
      cells = baseline_cells(load_baseline_v2(baseline_v2_path), genre)
      warnings = []
      z_scores = metrics.to_h do |key, value|
        cell = cells[key]
        if cell.nil?
          [ key, nil ]
        else
          warnings << key if cell["_placeholder"]
          [ key, z_simple(value.to_f, cell.fetch("mean", 0.0).to_f, cell.fetch("stdev", 0.0).to_f) ]
        end
      end
      base.merge(
        "version" => VERSION,
        "v2_metrics" => metrics,
        "v2_interference_index" => interference_index(text),
        "v2_z_scores" => z_scores,
        "v2_baseline_warnings" => warnings
      )
    end
    alias compute_all compute_all_v2

    private

    def v1_call(name, *args, **kwargs)
      [ "HumanizeKoreanMetrics", "Metrics" ].each do |constant_name|
        next unless Object.const_defined?(constant_name)

        provider = Object.const_get(constant_name)
        return provider.send(name, *args, **kwargs) if provider.respond_to?(name, true)
      end
      return Object.new.send(name, *args, **kwargs) if Object.private_method_defined?(name) || Object.method_defined?(name)

      raise NoMethodError, "metrics.rb does not provide #{name}"
    end

    def split_sentences(text)
      v1_private_call(:split_sentences, :_split_sentences, text)
    end

    def eojeols(text)
      v1_private_call(:eojeols, :_eojeols, text)
    end

    def strip_punct(token)
      v1_private_call(:strip_punct, :_strip_punct, token)
    end

    def v1_private_call(primary_name, fallback_name, *args)
      [ "HumanizeKoreanMetrics", "Metrics" ].each do |constant_name|
        next unless Object.const_defined?(constant_name)

        provider = Object.const_get(constant_name)
        return provider.send(primary_name, *args) if provider.respond_to?(primary_name, true)
        return provider.send(fallback_name, *args) if provider.respond_to?(fallback_name, true)
      end
      v1_call(fallback_name, *args)
    end

    def split_paragraphs(text)
      stripped = text.strip
      return [] if stripped.empty?

      stripped.split(PARAGRAPH_SPLIT_RE).map(&:strip).reject(&:empty?)
    end

    def last_eojeol(sentence)
      tokens = eojeols(sentence)
      tokens.empty? ? "" : strip_punct(tokens.last)
    end

    def all_tokens(text)
      eojeols(text).map { |token| strip_punct(token) }.reject(&:empty?)
    end

    def strip_markup(text)
      text.each_line.filter_map do |line|
        next if line.match?(MARKUP_ONLY_LINE_RE)

        line.sub(MARKUP_PREFIX_RE, "").chomp
      end.join("\n")
    end

    def load_baseline_v2(path)
      target = path || File.join(__dir__, "baseline_v2.json")
      return {} unless File.exist?(target)

      JSON.parse(File.read(target, encoding: "UTF-8"))
    end

    def baseline_cells(baseline, genre)
      genres = baseline.fetch("genres", {}) || {}
      genres[genre] || genres["essay"] || {}
    end

    def z_simple(value, mean, stdev)
      return nil if stdev <= 0

      (value - mean) / stdev
    end

    # Ruby has no stdlib equivalent of difflib.SequenceMatcher. This is its
    # autojunk=False longest-contiguous-match recursion, sufficient to preserve
    # the Python ratio used by change_rate.
    def sequence_match_size(a, b)
      index = Hash.new { |hash, key| hash[key] = [] }
      b.each_with_index { |value, position| index[value] << position }
      queue = [ [ 0, a.length, 0, b.length ] ]
      blocks = []
      until queue.empty?
        entry = queue.pop
        next if entry.nil?

        alo, ahi, blo, bhi = entry
        i, j, size = find_longest_match(a, index, alo, ahi, blo, bhi)
        next if size.zero?

        blocks << [ i, j, size ]
        queue << [ alo, i, blo, j ] if alo < i && blo < j
        queue << [ i + size, ahi, j + size, bhi ] if i + size < ahi && j + size < bhi
      end
      blocks.sort_by! { |block| [ block[0], block[1] ] }
      merged = []
      blocks.each do |i, j, size|
        last = merged[-1]
        if last && last[0] + last[2] == i && last[1] + last[2] == j
          last[2] += size
        else
          merged << [ i, j, size ]
        end
      end
      merged.sum { |(_, _, size)| size }
    end

    def find_longest_match(a, index, alo, ahi, blo, bhi)
      best_i = alo
      best_j = blo
      best_size = 0
      previous = {}
      (alo...ahi).each do |i|
        current = {}
        index[a[i]].each do |j|
          next if j < blo
          break if j >= bhi

          size = previous.fetch(j - 1, 0) + 1
          current[j] = size
          if size > best_size
            best_i = i - size + 1
            best_j = j - size + 1
            best_size = size
          end
        end
        previous = current
      end
      [ best_i, best_j, best_size ]
    end
  end
end
# rubocop:enable Metrics/ModuleLength, Metrics/ClassLength

if $PROGRAM_NAME == __FILE__
  options = { genre: "essay" }
  parser = OptionParser.new do |opts|
    opts.banner = "Usage: ruby metrics_v2.rb --input PATH [options]"
    opts.on("--input PATH", "Input text file path") { |value| options[:input] = value }
    opts.on("--genre GENRE", "essay/news/blog/qa/dialogue") { |value| options[:genre] = value }
    opts.on("--output PATH", "Output JSON path (optional)") { |value| options[:output] = value }
    opts.on("--baseline PATH", "Override v1.6 baseline JSON path") { |value| options[:baseline] = value }
    opts.on("--baseline-v2 PATH", "Override v2.0 baseline JSON path") { |value| options[:baseline_v2] = value }
  end
  parser.parse!
  abort parser.to_s unless options[:input]

  text = File.read(options[:input], encoding: "UTF-8")
  result = MetricsV2.compute_all_v2(text, genre: options[:genre], baseline_path: options[:baseline], baseline_v2_path: options[:baseline_v2])
  if options[:output]
    FileUtils.mkdir_p(File.dirname(File.expand_path(options[:output])))
    File.write(options[:output], JSON.pretty_generate(result), encoding: "UTF-8")
  end
  puts result.fetch("risk_band")
end
