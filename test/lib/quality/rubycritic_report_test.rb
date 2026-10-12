# frozen_string_literal: true

require "test_helper"
require_relative "../../../lib/quality/rubycritic_report"

module Quality
  class RubycriticReportTest < ActiveSupport::TestCase
    PATHS = %w[app/models app/services].freeze
    REPORT = {
      "score" => 79.19,
      "analysed_modules" => [
        { "path" => "app/a.rb", "rating" => "D", "cost" => 12.3, "churn" => 30, "complexity" => 200.0 },
        { "path" => "app/b.rb", "rating" => "A", "cost" => 0.5, "churn" => 40, "complexity" => 10.0 },
        { "path" => "app/c.rb", "rating" => "D", "cost" => 11.0, "churn" => 2, "complexity" => 300.0 },
        { "path" => "app/d.rb", "rating" => "C", "cost" => 3.0, "churn" => 20, "complexity" => 150.0 }
      ]
    }.freeze

    test "총점·파일 수·등급 분포·분석 범위를 요약한다" do
      md = to_markdown(REPORT)

      assert_includes md, "| 총점 | 79.19 |"
      assert_includes md, "| 분석 파일 | 4 |"
      assert_includes md, "| 등급 | A 1 / B 0 / C 1 / D 2 / F 0 |"
      assert_includes md, "| 범위 | `app/models` `app/services` |"
      assert_includes md, "2026-04-11"
    end

    test "변경 빈도 × 복잡도 순으로 우선 검토 후보를 고른다" do
      rows = candidate_rows(REPORT, top: 2)

      # 복잡도만 높은 c.rb(churn 2)와 변경만 잦은 b.rb(복잡도 10)는 둘 다 높은 a.rb·d.rb보다 뒤다.
      assert_equal [ "app/a.rb", "app/d.rb" ], rows.map { it[/`([^`]+)`/, 1] }
      assert_includes rows.first, "| 6000 | 30 | 200 | D | 12.3 |"
    end

    # RubyCritic 5.0.0 report.json의 모듈 모양(소수점 복잡도·비용, 그 밖의 키)을 따른다.
    test "소수점 복잡도는 곱한 뒤 반올림하고 표에는 반올림해 적는다" do
      report = report_with([
        { "name" => "Article", "path" => "app/models/article.rb", "smells" => [], "churn" => 42,
          "committed_at" => "2026-10-11 10:00:00 +0900", "complexity" => 164.41, "duplication" => 0,
          "methods_count" => 25, "cost" => 6.5763, "rating" => "C" }
      ])

      assert_includes candidate_rows(report).first, "| 6905 | 42 | 164 | C | 6.6 |"
    end

    test "우선순위가 같으면 경로 순으로 정렬한다" do
      modules = [ "app/z.rb", "app/a.rb", "app/m.rb" ].map do |path|
        { "path" => path, "rating" => "A", "cost" => 1.0, "churn" => 2, "complexity" => 10.0 }
      end

      assert_equal %w[app/a.rb app/m.rb app/z.rb], candidate_rows(report_with(modules)).map { it[/`([^`]+)`/, 1] }
    end

    test "분석한 모듈이 없으면 실패한다" do
      error = assert_raises(RubycriticReport::InvalidReport) { to_markdown(report_with([])) }
      assert_includes error.message, "no modules"
    end

    # git log가 실패하거나 작업 트리·기간 오류로 churn을 세지 못하면 순위가 무의미하다.
    test "모든 churn이 0이면 실패한다" do
      modules = REPORT["analysed_modules"].map { it.merge("churn" => 0) }

      error = assert_raises(RubycriticReport::InvalidReport) { to_markdown(report_with(modules)) }
      assert_includes error.message, "churn"
    end

    # RubyCritic가 필드명을 바꾸면 0으로 채운 표가 정상처럼 나오지 않게 한다.
    test "모듈 필드가 없으면 KeyError로 실패한다" do
      %w[path rating cost churn complexity].each do |key|
        modules = [ REPORT["analysed_modules"].first.except(key) ]

        assert_raises(KeyError, key) { to_markdown(report_with(modules)) }
      end
    end

    test "알 수 없는 등급이면 실패한다" do
      modules = [ REPORT["analysed_modules"].first.merge("rating" => "E") ]

      error = assert_raises(RubycriticReport::InvalidReport) { to_markdown(report_with(modules)) }
      assert_includes error.message, "E"
    end

    test "변경되지 않은 모듈과 변경된 모듈이 섞인 리포트는 유효하다" do
      modules = REPORT["analysed_modules"].map.with_index { |mod, index| mod.merge("churn" => index.zero? ? 0 : mod["churn"]) }

      assert_includes to_markdown(report_with(modules)), "| 분석 파일 | 4 |"
    end

    test "숫자 필드 null은 정상적인 0으로 요약하지 않는다" do
      %w[churn complexity cost].each do |key|
        modules = [ REPORT["analysed_modules"].first.merge(key => nil) ]
        assert_raises(TypeError, key) { to_markdown(report_with(modules)) }
      end
    end

    private

    def to_markdown(report, **)
      RubycriticReport.to_markdown(report, churn_after: "2026-04-11", paths: PATHS, **)
    end

    def candidate_rows(report, **)
      to_markdown(report, **).lines.grep(/\A\| \d+ \| `app/)
    end

    def report_with(modules)
      REPORT.merge("analysed_modules" => modules)
    end
  end
end
