# frozen_string_literal: true

require "test_helper"
require_relative "../../../lib/quality/rubycritic_report"

module Quality
  class RubycriticReportTest < ActiveSupport::TestCase
    REPORT = {
      "score" => 79.19,
      "analysed_modules" => [
        { "path" => "app/a.rb", "rating" => "D", "cost" => 12.3, "churn" => 30, "complexity" => 200.0 },
        { "path" => "app/b.rb", "rating" => "A", "cost" => 0.5, "churn" => 40, "complexity" => 10.0 },
        { "path" => "app/c.rb", "rating" => "D", "cost" => 11.0, "churn" => 2, "complexity" => 300.0 },
        { "path" => "app/d.rb", "rating" => "C", "cost" => 3.0, "churn" => 20, "complexity" => 150.0 }
      ]
    }.freeze

    test "총점·파일 수·등급 분포를 요약한다" do
      md = RubycriticReport.to_markdown(REPORT, churn_after: "2026-04-11")

      assert_includes md, "| 총점 | 79.19 |"
      assert_includes md, "| 분석 파일 | 4 |"
      assert_includes md, "| 등급 | A 1 / B 0 / C 1 / D 2 / F 0 |"
      assert_includes md, "2026-04-11"
    end

    test "변경 빈도 × 복잡도 순으로 우선 검토 후보를 고른다" do
      rows = RubycriticReport.to_markdown(REPORT, churn_after: "2026-04-11", top: 2)
        .lines.grep(/\A\| \d+ \| `app/)

      # 복잡도만 높은 c.rb(churn 2)와 변경만 잦은 b.rb(복잡도 10)는 둘 다 높은 a.rb·d.rb보다 뒤다.
      assert_equal [ "app/a.rb", "app/d.rb" ], rows.map { it[/`([^`]+)`/, 1] }
      assert_includes rows.first, "| 6000 | 30 | 200 | D | 12.3 |"
    end
  end
end
