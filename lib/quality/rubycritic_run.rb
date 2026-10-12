# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

require "date"
require "open3"

module Quality
  # bin/rubycritic의 입력 검사. 입력이 무너지면 RubyCritic은 churn을 0이나 1로 채우고 정상 종료해
  # 그럴듯한 요약이 나오므로(#1087), 분석 전에 실행 조건을 확인한다.
  module RubycriticRun
    CHURN_MONTHS = 6
    DATE_FORMAT = /\A\d{4}-\d{2}-\d{2}\z/

    class << self
      # RUBYCRITIC_CHURN_AFTER를 해석한다. 비어 있으면 최근 6개월이다. 값은 RubyCritic 안에서
      # 셸 문자열(--after='...')로 들어가므로 Date로 해석한 뒤 다시 찍은 값만 넘긴다.
      #: (String? value, ?today: Date) -> String
      def churn_after(value, today: Date.today)
        value = value.to_s.strip
        return (today << CHURN_MONTHS).iso8601 if value.empty?

        date = parse_date(value)
        raise ArgumentError, "RUBYCRITIC_CHURN_AFTER is in the future: #{value}" if date > today

        date.iso8601
      end

      # 분석을 시작하면 안 되는 이유를 돌려준다. 비어 있으면 통과다.
      #: (root: String, paths: Array[String]) -> Array[String]
      def preflight_errors(root:, paths:)
        missing = paths.reject { File.directory?(File.join(root, it)) }
        errors = []
        errors << "analysis paths not found: #{missing.join(", ")}" if missing.any?
        errors.concat(git_errors(root))
      end

      private

      #: (String value) -> Date
      def parse_date(value)
        raise Date::Error unless value.match?(DATE_FORMAT)

        Date.iso8601(value)
      rescue Date::Error
        raise ArgumentError, "RUBYCRITIC_CHURN_AFTER must be an ISO 8601 date (YYYY-MM-DD): #{value.inspect}"
      end

      # churn은 git log로 센다. 얕은 클론이면 전부 1, 작업 트리나 하위 디렉터리면 RubyCritic이
      # 다른 .git을 루트로 잡아 전부 0이 된다.
      #: (String root) -> Array[String]
      def git_errors(root)
        output, status = Open3.capture2e("git", "-C", root, "rev-parse", "--is-shallow-repository",
                                         "--show-toplevel", "--absolute-git-dir", "--path-format=absolute",
                                         "--git-common-dir")
        return [ "not a git repository: #{root}" ] unless status.success?

        shallow, toplevel, git_dir, common_dir = output.lines.map(&:chomp)
        errors = []
        errors << "shallow clone: churn needs full history (fetch-depth: 0)" if shallow == "true"
        errors << "git worktree: run in a regular clone (RubyCritic resolves the parent .git)" if git_dir != common_dir
        errors << "#{root} is not the git top level (#{toplevel})" unless same_path?(toplevel, root)
        errors
      end

      #: (String? left, String right) -> bool
      def same_path?(left, right)
        !left.nil? && File.realpath(left) == File.realpath(right)
      end
    end
  end
end
