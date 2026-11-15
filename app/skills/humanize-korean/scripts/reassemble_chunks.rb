#!/usr/bin/env ruby
# typed: false
# frozen_string_literal: true
# rbs_inline: enabled

# Humanize KR v2.0.1 — 청크 윤문 결과 재조립기.
#
# `prepare_monolith_input.rb --chunk`가 만든 chunk_manifest.json 순서대로
# 청크별 윤문 결과를 병합한다. 문서 말미 각주 passthrough 청크는 원문 그대로
# 보존하고, 원문 청크의 경계 공백을 복원해 원문을 그대로 넣었을 때 왕복 항등을
# 보장한다.

require "digest"
require "json"
require "optparse"

module HumanizeKoreanReassembleChunks
  class << self
    def run(argv)
      options = parse_options(argv)
      run_dir = options.fetch(:run_dir)
      manifest = load_manifest(run_dir)
      text = load_source(run_dir, manifest)
      chunks = manifest.fetch("chunks")

      verify_source!(text, manifest, chunks)
      verify_rewritten_files!(run_dir, chunks)

      result = reassemble(run_dir, text, chunks)
      output_path = File.join(run_dir, options.fetch(:output))
      File.write(output_path, result.fetch(:output), encoding: "UTF-8")

      report = build_report(text, result)
      report_path = File.join(run_dir, options.fetch(:report))
      File.write(report_path, JSON.pretty_generate(report), encoding: "UTF-8")

      print_result(output_path, chunks, text, result, report)
      options.fetch(:strict) && result.fetch(:warnings).any? ? 1 : 0
    end

    private

    def parse_options(argv)
      options = { output: "03_reassembled.md", report: "03_reassembly_report.json", strict: false }
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: reassemble_chunks.rb --run-dir DIR [options]"
        opts.on("--run-dir DIR", "chunk_manifest.json 이 있는 런 디렉터리") { |value| options[:run_dir] = value }
        opts.on("--output FILE", "병합 결과 파일명") { |value| options[:output] = value }
        opts.on("--report FILE", "문자 수 대사 리포트 파일명") { |value| options[:report] = value }
        opts.on("--strict", "문자 수 대사 경고를 오류(exit 1)로 처리") { options[:strict] = true }
      end
      parser.parse!(argv)
      raise OptionParser::MissingArgument, "--run-dir" unless options[:run_dir]

      options
    rescue OptionParser::ParseError => error
      warn error.message
      warn parser
      exit 2
    end

    def load_manifest(run_dir)
      path = File.join(run_dir, "chunk_manifest.json")
      abort "chunk_manifest.json not found in #{run_dir}; run prepare_monolith_input.rb --chunk first" unless File.exist?(path)

      JSON.parse(File.read(path, encoding: "UTF-8"))
    end

    def load_source(run_dir, manifest)
      path = File.join(run_dir, manifest.fetch("source_file"))
      abort "source file not found: #{path}" unless File.exist?(path)

      File.read(path, encoding: "UTF-8")
    end

    def verify_source!(text, manifest, chunks)
      sha = Digest::SHA256.hexdigest(text)
      abort "입력이 청킹 이후 변경됨 (sha256 불일치) — prepare_monolith_input.rb --chunk 재실행 필요" if sha != manifest["source_sha256"]

      joined = chunks.map { |chunk| text[chunk.fetch("start")...chunk.fetch("end")] }.join
      return if joined == text

      abort "manifest 구간 연결이 원문과 불일치 — manifest 손상, --chunk 재실행 필요"
    end

    def verify_rewritten_files!(run_dir, chunks)
      missing = chunks.filter_map do |chunk|
        next if chunk.fetch("passthrough")

        filename = chunk.fetch("rewritten_file")
        filename unless File.exist?(File.join(run_dir, filename))
      end
      return if missing.empty?

      abort "윤문 결과 파일 누락 #{missing.length}건: #{missing.join(", ") }"
    end

    def reassemble(run_dir, text, chunks)
      warnings = []
      report_chunks = []
      pieces = chunks.map do |chunk|
        original = text[chunk.fetch("start")...chunk.fetch("end")]
        if chunk.fetch("passthrough")
          report_chunks << { "index" => chunk.fetch("index"), "passthrough" => true, "orig_chars" => original.length }
          next original
        end

        rewritten = File.read(File.join(run_dir, chunk.fetch("rewritten_file")), encoding: "UTF-8")
        core_original = original.strip
        core_rewritten = rewritten.strip
        abort "청크 #{chunk.fetch("index")} 윤문 결과(#{chunk.fetch("rewritten_file")})가 비어 있음 — 유실 사고" if !core_original.empty? && core_rewritten.empty?

        piece, ratio = build_piece(original, core_original, core_rewritten)
        add_ratio_warning(warnings, chunk.fetch("index"), core_original, core_rewritten, ratio)
        report_chunks << {
          "index" => chunk.fetch("index"), "passthrough" => false,
          "orig_chars" => core_original.length, "rewritten_chars" => core_rewritten.length,
          "ratio" => ratio.round(3)
        }
        piece
      end
      { output: pieces.join, warnings: warnings, chunks: report_chunks }
    end

    def build_piece(original, core_original, core_rewritten)
      return [ original, 1.0 ] if core_original.empty?

      leading = original[/\A\s*/]
      trailing = original[/\s*\z/]
      [ leading + core_rewritten + trailing, core_rewritten.length.to_f / core_original.length ]
    end

    def add_ratio_warning(warnings, index, original, rewritten, ratio)
      return unless ratio < 0.5 || ratio > 2.0

      concern = ratio < 0.5 ? "유실 의심" : "증식 의심"
      warnings << "청크 #{index}: 원문 #{original.length}자 → #{rewritten.length}자 (#{format("%.0f%%", ratio * 100)}) — #{concern}"
    end

    def build_report(text, result)
      output = result.fetch(:output)
      {
        "source_chars" => text.length,
        "output_chars" => output.length,
        "total_ratio" => text.empty? ? nil : (output.length.to_f / text.length).round(3),
        "warnings" => result.fetch(:warnings),
        "chunks" => result.fetch(:chunks)
      }
    end

    def print_result(output_path, chunks, text, result, report)
      puts "output=#{output_path}"
      puts "chunks=#{chunks.length}"
      puts "source_chars=#{text.length}  output_chars=#{result.fetch(:output).length}  total_ratio=#{report.fetch("total_ratio")}"
      puts "warnings=#{result.fetch(:warnings).length}"
      result.fetch(:warnings).each { |warning| puts "WARNING: #{warning}" }
    end
  end
end

exit HumanizeKoreanReassembleChunks.run(ARGV) if $PROGRAM_NAME == __FILE__
