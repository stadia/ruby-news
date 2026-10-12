# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

module Quality
  # RubyCritic의 report.json을 기준선 문서에 붙일 마크다운 요약으로 옮긴다.
  #
  # 우선 검토 후보는 변경 빈도(churn) × 복잡도(complexity) 순이다. 자주 바뀌지만 단순한 파일이나
  # 복잡하지만 거의 안 바뀌는 파일보다, 둘 다 높은 파일을 먼저 본다(docs/quality/rubycritic.md).
  module RubycriticReport
    RATINGS = %w[A B C D F].freeze

    # report.json이 요약할 수 없는 모양이다(분석 0건, churn 전부 0, 알 수 없는 등급).
    class InvalidReport < StandardError; end

    class << self
      # 입력이 무너진 리포트를 정상 표로 찍지 않도록 먼저 검증한다. 필드가 없으면 KeyError다.
      #: (Hash[String, untyped] report, churn_after: String, paths: Array[String], ?top: Integer) -> String
      def to_markdown(report, churn_after:, paths:, top: 10)
        modules = report.fetch("analysed_modules")
        validate!(modules)
        <<~MD
          ## RubyCritic

          | 항목 | 값 |
          |---|---|
          | 총점 | #{report.fetch("score")} |
          | 분석 파일 | #{modules.size} |
          | 등급 | #{rating_counts(modules)} |
          | 범위 | #{paths.map { "`#{it}`" }.join(" ")} |
          | churn 기간 | #{churn_after} 이후 |

          ### 우선 검토 후보 (churn × 복잡도 상위 #{top})

          | # | 파일 | churn × 복잡도 | churn | 복잡도 | 등급 | 비용 |
          |---|---|---|---|---|---|---|
          #{candidate_rows(modules, top).join("\n")}
        MD
      end

      private

      # 분석 경로가 없거나 git log가 실패하면 RubyCritic은 0건·churn 0으로 정상 종료한다.
      #: (Array[Hash[String, untyped]] modules) -> void
      def validate!(modules)
        raise InvalidReport, "no modules analysed" if modules.empty?

        unknown = modules.map { it.fetch("rating") } - RATINGS
        raise InvalidReport, "unknown ratings: #{unknown.uniq.join(", ")}" if unknown.any?
        raise InvalidReport, "churn is 0 for every module; git history was not read" if modules.all? { it.fetch("churn").to_i.zero? }
      end

      #: (Array[Hash[String, untyped]] modules) -> String
      def rating_counts(modules)
        counts = modules.map { it.fetch("rating") }.tally
        RATINGS.map { "#{it} #{counts.fetch(it, 0)}" }.join(" / ")
      end

      #: (Array[Hash[String, untyped]] modules, Integer top) -> Array[String]
      def candidate_rows(modules, top)
        # 동점은 경로 순으로 고정해 실행마다 표 순서가 같게 한다.
        modules.sort_by { [ -priority(it), it.fetch("path") ] }.first(top).each_with_index.map do |mod, index|
          "| #{index + 1} | `#{mod.fetch("path")}` | #{priority(mod)} | #{mod.fetch("churn").to_i} | " \
            "#{mod.fetch("complexity").to_f.round} | #{mod.fetch("rating")} | #{mod.fetch("cost").to_f.round(1)} |"
        end
      end

      #: (Hash[String, untyped] mod) -> Integer
      def priority(mod)
        (mod.fetch("churn").to_i * mod.fetch("complexity").to_f).round
      end
    end
  end
end
