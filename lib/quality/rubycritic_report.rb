# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

module Quality
  # RubyCritic의 report.json을 기준선 문서·GitHub Actions step summary용 마크다운으로 옮긴다.
  #
  # 우선 검토 후보는 변경 빈도(churn) × 복잡도(complexity) 순이다. 자주 바뀌지만 단순한 파일이나
  # 복잡하지만 거의 안 바뀌는 파일보다, 둘 다 높은 파일을 먼저 본다(docs/quality/rubycritic.md).
  module RubycriticReport
    RATINGS = %w[A B C D F].freeze

    class << self
      #: (Hash[String, untyped] report, churn_after: String, ?top: Integer) -> String
      def to_markdown(report, churn_after:, top: 10)
        modules = report.fetch("analysed_modules")
        <<~MD
          ## RubyCritic

          | 항목 | 값 |
          |---|---|
          | 총점 | #{report.fetch("score")} |
          | 분석 파일 | #{modules.size} |
          | 등급 | #{rating_counts(modules)} |
          | churn 기간 | #{churn_after} 이후 |

          ### 우선 검토 후보 (churn × 복잡도 상위 #{top})

          | # | 파일 | churn × 복잡도 | churn | 복잡도 | 등급 | 비용 |
          |---|---|---|---|---|---|---|
          #{candidate_rows(modules, top).join("\n")}
        MD
      end

      private

      #: (Array[Hash[String, untyped]] modules) -> String
      def rating_counts(modules)
        counts = modules.map { it["rating"] }.tally
        RATINGS.map { "#{it} #{counts.fetch(it, 0)}" }.join(" / ")
      end

      #: (Array[Hash[String, untyped]] modules, Integer top) -> Array[String]
      def candidate_rows(modules, top)
        modules.sort_by { -priority(it) }.first(top).each_with_index.map do |mod, index|
          "| #{index + 1} | `#{mod["path"]}` | #{priority(mod)} | #{mod["churn"].to_i} | " \
            "#{mod["complexity"].to_f.round} | #{mod["rating"]} | #{mod["cost"].to_f.round(1)} |"
        end
      end

      #: (Hash[String, untyped] mod) -> Integer
      def priority(mod)
        (mod["churn"].to_i * mod["complexity"].to_f).round
      end
    end
  end
end
