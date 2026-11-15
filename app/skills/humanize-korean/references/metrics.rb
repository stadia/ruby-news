#!/usr/bin/env ruby
# typed: false
# frozen_string_literal: true
# rbs_inline: enabled

# Humanize KR v1.6 quantitative metrics calculator.
#
# Standard-library-only Ruby port of metrics.py. When run directly it reads an
# input file, optionally writes the computed JSON, and prints the risk band.

require "json"
require "optparse"
require "fileutils"

# rubocop:disable Metrics/ModuleLength
module HumanizeKoreanMetrics
  VERSION = "v1.6"

  ENDING_COMMA_RE = /(?:고|며|지만|면서|아서|어서)\s*,/
  EOJEOL_SPLIT_RE = /\s+/
  SENTENCE_SPLIT_RE = /(?<=[.!?。])\s+/
  HANJA_SUFFIXES = [ "성", "적", "화" ].freeze
  HANJA_BLOCK = [ "있는화", "되는화", "맞아", "와서" ].freeze
  PUNCT_STRIP_RE = /[\.,!?;:\(\)\[\]\{\}\"'`~、。“”‘’\-]+/

  class << self
    # Ratio of sentences containing one or more commas (0..1).
    def comma_inclusion_rate(text)
      sentences = split_sentences(text)
      return 0.0 if sentences.empty?

      sentences.count { |sentence| sentence.include?(",") }.fdiv(sentences.length)
    end

    # Average comma count per sentence.
    def comma_usage_rate(text)
      sentences = split_sentences(text)
      return 0.0 if sentences.empty?

      sentences.sum { |sentence| sentence.count(",") }.fdiv(sentences.length)
    end

    # Ratio of connective-ending positions immediately followed by a comma.
    def ending_comma_rate(text)
      return 0.0 if text.strip.empty?

      boundary_endings = text.scan(/(?:고|며|지만|면서|아서|어서)(?=[\s,.!?、。]|$)/)
      return 0.0 if boundary_endings.empty?

      text.scan(ENDING_COMMA_RE).length.fdiv(boundary_endings.length)
    end

    # Average eojeol count of comma-delimited segments across sentences.
    def comma_segment_length(text)
      segment_lengths = split_sentences(text).flat_map do |sentence|
        if !sentence.include?(",")
          [ eojeols(sentence).length ]
        else
          sentence.split(",").filter_map do |segment|
            stripped = segment.strip
            eojeols(stripped).length unless stripped.empty?
          end
        end
      end
      return 0.0 if segment_lengths.empty?

      segment_lengths.sum.fdiv(segment_lengths.length)
    end

    # Count occurrences of conclusion-pivot lexicon items.
    def conclusion_pivot_count(text, lexicon = nil)
      items = lexicon || [ "결론적으로", "따라서", "이를 통해", "그러므로" ]
      items.sum { |word| text.scan(word).length }
    end

    # Count occurrences of safe-balance hedge lexicon items.
    def safe_balance_count(text, lexicon = nil)
      items = lexicon || [ "양쪽 모두", "두 가지 모두", "장점도 있지만", "신중하게", "균형" ]
      items.sum { |word| text.scan(word).length }
    end

    # Token-level density of -성 / -적 / -화 endings (0..1).
    def hanja_nominalizer_density(text)
      tokens = eojeols(text).map { |token| strip_punct(token) }.reject(&:empty?)
      return 0.0 if tokens.empty?

      hits = tokens.count do |token|
        token.length >= 2 && !HANJA_BLOCK.include?(token) && HANJA_SUFFIXES.include?(token[-1])
      end
      hits.fdiv(tokens.length)
    end

    # Type-token ratio over eojeols (unique / total).
    def lexical_diversity(text)
      tokens = eojeols(text).map { |token| strip_punct(token) }.reject(&:empty?)
      return 0.0 if tokens.empty?

      tokens.uniq.length.fdiv(tokens.length)
    end

    # Compute all v1.6 metrics, z-scores, and risk band for one document.
    def compute_all(text, genre: "essay", baseline_path: nil)
      baseline = load_baseline(baseline_path)
      cells, fallback_warning = resolve_genre_cells(baseline, genre)
      lexicons = baseline.fetch("lexicons", {}) || {}
      pivot_lexicon = lexicons["conclusion_pivot"] || [ "결론적으로", "따라서", "이를 통해", "그러므로" ]
      safe_lexicon = lexicons["safe_balance"] || [ "양쪽 모두", "두 가지 모두", "장점도 있지만", "신중하게", "균형" ]

      metrics = {
        "comma_inclusion_rate" => comma_inclusion_rate(text),
        "comma_usage_rate" => comma_usage_rate(text),
        "ending_comma_rate" => ending_comma_rate(text),
        "comma_segment_length" => comma_segment_length(text),
        "conclusion_pivot_count" => conclusion_pivot_count(text, pivot_lexicon),
        "safe_balance_count" => safe_balance_count(text, safe_lexicon),
        "hanja_nominalizer_density" => hanja_nominalizer_density(text),
        "lexical_diversity" => lexical_diversity(text)
      }

      z_scores = {}
      [
        [ "comma_inclusion_rate", true ],
        [ "comma_usage_rate", false ],
        [ "ending_comma_rate", true ],
        [ "comma_segment_length", false ]
      ].each do |key, percent|
        cell = cells[key]
        z_scores[key] = cell ? z(metrics[key], cell["human"], cell["ai"], percent: percent) : nil
      end
      z_scores["hanja_nominalizer_density"] = z(metrics["hanja_nominalizer_density"] * 100, 6.0, 12.0, percent: false)
      z_scores["lexical_diversity"] = z(metrics["lexical_diversity"], 0.65, 0.55, percent: false)

      lexicon_hits = {
        "conclusion_pivot_count" => metrics["conclusion_pivot_count"].to_i,
        "safe_balance_count" => metrics["safe_balance_count"].to_i
      }
      risk_band, risk_score = classify_risk(z_scores, lexicon_hits)

      result = {
        "version" => VERSION,
        "genre" => genre,
        "char_count" => text.length,
        "metrics" => metrics,
        "z_scores" => z_scores,
        "risk_band" => risk_band,
        "risk_score" => risk_score,
        "evidence" => {
          "conclusion_pivots" => evidence_spans(text, pivot_lexicon),
          "safe_balances" => evidence_spans(text, safe_lexicon)
        }
      }
      result["warning"] = fallback_warning if fallback_warning
      result
    end

    def main(argv = ARGV)
      options = { genre: "essay", output: nil, baseline: nil }
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: metrics.rb --input PATH [options]"
        opts.on("--input PATH", "Input text file path") { |path| options[:input] = path }
        opts.on("--genre GENRE", "essay/poetry/abstract/...") { |genre| options[:genre] = genre }
        opts.on("--output PATH", "Output JSON path (optional)") { |path| options[:output] = path }
        opts.on("--baseline PATH", "Override baseline JSON path") { |path| options[:baseline] = path }
      end
      parser.parse!(argv)
      raise OptionParser::MissingArgument, "--input" unless options[:input]

      text = File.read(options[:input], encoding: "UTF-8")
      result = compute_all(text, genre: options[:genre], baseline_path: options[:baseline])

      if options[:output]
        FileUtils.mkdir_p(File.dirname(File.expand_path(options[:output])))
        File.write(options[:output], JSON.pretty_generate(result) + "\n", encoding: "UTF-8")
      end

      puts result["risk_band"]
      0
    rescue OptionParser::ParseError => error
      warn error.message
      warn parser
      1
    end

    private

    def split_sentences(text)
      stripped = text.strip
      return [] if stripped.empty?

      stripped.split(SENTENCE_SPLIT_RE).flat_map do |part|
        part.split("\n").map(&:strip).reject(&:empty?)
      end
    end

    def eojeols(text)
      text.strip.split(EOJEOL_SPLIT_RE).reject(&:empty?)
    end

    def strip_punct(token)
      token.gsub(PUNCT_STRIP_RE, "")
    end

    def default_baseline_path
      File.join(File.dirname(File.expand_path(__FILE__)), "baseline.json")
    end

    def load_baseline(path)
      JSON.parse(File.read(path || default_baseline_path, encoding: "UTF-8"))
    end

    def resolve_genre_cells(baseline, genre)
      genres = baseline.fetch("genres", {}) || {}
      requested = genres[genre]
      fallback = nil
      unless requested
        fallback = "baseline_genre_null:#{genre}->essay"
        requested = genres["essay"] || {}
      end
      global_average = baseline.fetch("global_average", {}) || {}
      merged = {}
      (requested.keys | global_average.keys).each do |key|
        cell = requested[key] || global_average[key]
        merged[key] = cell if cell
      end
      [ merged, fallback ]
    end

    def z(value, human, ai, percent:)
      return nil if human.nil? || ai.nil?

      measured = percent ? value * 100 : value
      standard_deviation = (ai - human).abs / 2.0
      return 0.0 if standard_deviation.zero?

      (measured - human) / standard_deviation
    end

    def classify_risk(z_scores, lexicon_hits)
      score = 0
      %w[comma_inclusion_rate ending_comma_rate comma_segment_length].each do |key|
        score += 2 if z_scores[key] && z_scores[key] > 1.0
      end
      score += 1 if z_scores["lexical_diversity"] && z_scores["lexical_diversity"] < -1.0
      score += 1 if lexicon_hits.fetch("conclusion_pivot_count", 0) >= 2
      score += 1 if lexicon_hits.fetch("safe_balance_count", 0) >= 2
      score += 1 if z_scores["hanja_nominalizer_density"] && z_scores["hanja_nominalizer_density"] > 1.0

      band = if score >= 6
        "high"
      elsif score >= 4
        "medium"
      else
        "low"
      end
      [ band, score ]
    end

    def evidence_spans(text, lexicon)
      lexicon.select { |word| text.include?(word) }
    end
  end
end
# rubocop:enable Metrics/ModuleLength

if File.expand_path($PROGRAM_NAME) == File.expand_path(__FILE__)
  options = { genre: "essay" }
  parser = OptionParser.new do |opts|
    opts.banner = "Usage: ruby metrics.rb --input PATH [options]"
    opts.on("--input PATH", "Input text file path") { |value| options[:input] = value }
    opts.on("--genre GENRE", "essay/poetry/abstract/...") { |value| options[:genre] = value }
    opts.on("--output PATH", "Output JSON path (optional)") { |value| options[:output] = value }
    opts.on("--baseline PATH", "Override baseline JSON path") { |value| options[:baseline] = value }
  end
  parser.parse!
  abort parser.to_s unless options[:input]

  result = HumanizeKoreanMetrics.compute_all(
    File.read(options[:input], encoding: "UTF-8"),
    genre: options[:genre],
    baseline_path: options[:baseline]
  )
  if options[:output]
    FileUtils.mkdir_p(File.dirname(File.expand_path(options[:output])))
    File.write(options[:output], JSON.pretty_generate(result), encoding: "UTF-8")
  end
  puts result.fetch("risk_band")
end
