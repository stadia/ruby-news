# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

require "flog"

module Quality
  class FlogParser
    # app/skills는 독립 CLI 스크립트와 참고 자료이며 Zeitwerk에서도 제외된다.
    EXCLUDE_PATTERNS = %w[
      app/components/
      app/views/
      app/skills/
    ].freeze

    def initialize(paths)
      @paths = Array(paths).flat_map do |p|
        if File.directory?(p)
          Dir.glob(File.join(p, "**", "*.rb"))
        else
          p
        end
      end.reject { |file| EXCLUDE_PATTERNS.any? { |pattern| file.include?(pattern) } }
    end

    def parse
      flog = Flog.new
      flog.flog(*@paths)

      totals = flog.totals.reject { |name, _| name.end_with?("#none", ".none") }
      return { method_max: 0.0, class_max: 0.0 } if totals.empty?

      {
        method_max: totals.values.max,
        class_max: max_class_score(totals)
      }
    end

    private

    def max_class_score(totals)
      totals
        .group_by { |method_name, _| method_name.split(/[#.]/, 2).first }
        .values
        .map { |entries| entries.sum { |_, score| score } }
        .max
    end
  end
end
