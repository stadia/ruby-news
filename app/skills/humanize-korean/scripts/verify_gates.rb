#!/usr/bin/env ruby
# typed: false
# frozen_string_literal: true
# rbs_inline: enabled

# Tier 1 구조 게이트 — 4축 통합 결정적 사후 검증 (LLM 콜 0).
# Exit code: 0=OK, 1=WARN, 2=ABORT, 3=execution error.

require "json"
require "optparse"
require_relative "golden/checks"
require_relative "../references/metrics_v2"

# rubocop:disable Metrics/ModuleLength
module HumanizeKoreanVerifyGates
  SUMMARY_BLOCK_RE = /<!--\s*HUMANIZE-SUMMARY\b.*/m
  S1_CANDIDATE_METRICS = %w[
    comma_inclusion_rate comma_usage_rate ending_comma_rate comma_segment_length
    hanja_nominalizer_density
  ].freeze
  S1_SELECT_Z = 2.0
  S1_ACHIEVED_Z = 1.0
  S1_MISSED_Z = 2.0
  S1_OVERCORRECT_Z = -1.5
  ANNIHILATION_MIN_BEFORE = 5

  class << self
    def strip_summary_block(text) = text.sub(SUMMARY_BLOCK_RE, "").strip
    def normalize_sentence(sentence) = sentence.gsub(/\s+/, " ").strip

    def split_sentences(text)
      MetricsV2.send(:split_sentences, text)
    end

    def sentence_touch_rate(before, after)
      before_sentences = split_sentences(before).map { |sentence| normalize_sentence(sentence) }.reject(&:empty?)
      return [ 0.0, 0, 0 ] if before_sentences.empty?

      after_sentences = split_sentences(after).map { |sentence| normalize_sentence(sentence) }.to_h { |sentence| [ sentence, true ] }
      touched = before_sentences.count { |sentence| !after_sentences.key?(sentence) }
      [ touched.fdiv(before_sentences.length), touched, before_sentences.length ]
    end

    def judge_s1_targets(z_before, z_after)
      results = []
      warn = false
      S1_CANDIDATE_METRICS.each do |key|
        before = z_before[key]
        next if before.nil? || before <= S1_SELECT_Z

        after = z_after[key]
        if after.nil?
          verdict = "판정불가 (after z 없음)"
        elsif after <= S1_OVERCORRECT_Z
          verdict = "과교정"
          warn = true
        elsif after <= S1_ACHIEVED_Z
          verdict = "달성"
        elsif after > S1_MISSED_Z
          verdict = "미달"
          warn = true
        else
          verdict = "부분 개선"
        end
        results << {
          "metric" => key,
          "z_before" => before.round(2),
          "z_after" => after&.round(2),
          "verdict" => verdict
        }
      end
      [ results, warn ]
    end

    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    def main(argv = ARGV)
      options = { genre: "essay", json: false, ignore_markup: false }
      parser = OptionParser.new do |opts|
        opts.banner = "usage: ruby verify_gates.rb --before PATH --after PATH [--genre GENRE] [--json] [--ignore-markup]"
        opts.on("--before PATH", "원문 경로 (01_input.txt)") { |value| options[:before] = value }
        opts.on("--after PATH", "윤문본 경로 (final.md)") { |value| options[:after] = value }
        opts.on("--genre GENRE", "essay/column/report/blog/abstract") { |value| options[:genre] = value }
        opts.on("--json", "구조화 JSON 출력 병기") { options[:json] = true }
        opts.on("--ignore-markup", "문자율 축에서 마크업 제외") { options[:ignore_markup] = true }
      end
      parser.parse!(argv)
      raise OptionParser::MissingArgument, "--before" unless options[:before]
      raise OptionParser::MissingArgument, "--after" unless options[:after]

      [ options[:before], options[:after] ].each do |path|
        unless File.exist?(path)
          warn "error: 파일 없음: #{path}"
          return 3
        end
      end

      begin
        before = strip_summary_block(File.read(options[:before], encoding: "UTF-8"))
        after = strip_summary_block(File.read(options[:after], encoding: "UTF-8"))
      rescue SystemCallError => error
        warn "error: 파일 읽기 실패: #{error}"
        return 3
      end

      report = { "genre" => options[:genre] }
      warn_gate = false

      rate = MetricsV2.change_rate(before, after, ignore_markup: options[:ignore_markup])
      abort_gate = rate >= MetricsV2::CHANGE_RATE_ABORT
      warn_gate ||= rate >= MetricsV2::CHANGE_RATE_WARN && rate < MetricsV2::CHANGE_RATE_ABORT
      scope = options[:ignore_markup] ? "본문만 (마크업 제외)" : "전문"
      p0_verdict = if abort_gate
        "ABORT — 강제 중단. 윤문본 채택 금지"
      elsif rate >= MetricsV2::CHANGE_RATE_WARN
        "WARN — 과윤문 경고"
      else
        "OK"
      end
      report["change_rate"] = { "rate" => rate.round(4), "scope" => scope, "verdict" => p0_verdict }
      puts format("[P0 문자율] %.1f%% [%s] — %s (경고 %.0f%% / 중단 %.0f%%)", rate * 100, scope, p0_verdict, MetricsV2::CHANGE_RATE_WARN * 100, MetricsV2::CHANGE_RATE_ABORT * 100)

      begin
        z_before = MetricsV2.compute_all_v2(before, genre: options[:genre]).fetch("z_scores")
        z_after = MetricsV2.compute_all_v2(after, genre: options[:genre]).fetch("z_scores")
      rescue StandardError => error
        z_before = {}
        z_after = {}
        warn "[P1 목표달성] 판정 불가 (metrics 오류: #{error})"
      end
      s1_results, s1_warn = judge_s1_targets(z_before, z_after)
      warn_gate ||= s1_warn
      report["s1_targets"] = s1_results
      if s1_results.empty?
        puts "[P1 목표달성] N/A — 구조 진단 (어휘 S1 앵커 없음)"
      else
        s1_results.each do |result|
          after_z = result["z_after"] ? format("%+.2f", result["z_after"]) : "?"
          puts format("[P1 목표달성] %s: z %+.2f → %s  %s", result["metric"], result["z_before"], after_z, result["verdict"])
        end
      end

      antithesis_before = MetricsV2.antithesis_count(before)
      antithesis_after = MetricsV2.antithesis_count(after)
      annihilated = antithesis_before >= ANNIHILATION_MIN_BEFORE && antithesis_after.zero?
      warn_gate ||= annihilated
      antithesis_verdict = if annihilated
        "FAIL — 전멸"
      elsif antithesis_before >= ANNIHILATION_MIN_BEFORE
        "OK"
      else
        "스킵 (원문 대구 < 5)"
      end
      report["antithesis"] = { "before" => antithesis_before, "after" => antithesis_after, "verdict" => antithesis_verdict }
      puts "[P2 전멸] C-8 대구 #{antithesis_before} → #{antithesis_after} — #{antithesis_verdict}"

      failures = HumanizeKoreanGoldenChecks.run_checks(before, after)
      warn_gate ||= failures.any?
      report["golden"] = failures.map { |failure| { "code" => failure.code, "message" => failure.message } }
      if failures.any?
        puts "[P3 golden] FAIL — #{failures.length}건:"
        failures.each { |failure| puts "    FAIL #{failure}" }
      else
        puts "[P3 golden] PASS (수치 주입·각주·인용·register 이상 없음)"
      end

      touch_rate, touched, total = sentence_touch_rate(before, after)
      report["sentence_touch"] = { "rate" => touch_rate.round(4), "touched" => touched, "total" => total }
      puts format("[P4 터치율] %.1f%% (%d/%d 문장) — 보고 전용", touch_rate * 100, touched, total)
      dropped = HumanizeKoreanGoldenChecks.dropped_numbers(before, after)
      report["numbers_dropped"] = dropped
      puts "[P4 수치소실] 관찰: #{dropped} (문장 병합·표기 통합이면 정상 — exit 미반영, 확인 요망)" if dropped.any?

      verdict, code = if abort_gate
        [ "ABORT — 강제 중단. 윤문본 채택 금지", 2 ]
      elsif warn_gate
        [ "WARN — 경고. 사용자 고지 + finalize 승급", 1 ]
      else
        [ "OK — 수렴", 0 ]
      end
      report["gate"] = { "verdict" => verdict, "exit_code" => code }
      puts "gate: #{verdict}"
      puts JSON.pretty_generate(report) if options[:json]
      code
    rescue OptionParser::ParseError => error
      warn error.message
      warn parser
      3
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
  end
end
# rubocop:enable Metrics/ModuleLength

exit HumanizeKoreanVerifyGates.main if $PROGRAM_NAME == __FILE__
