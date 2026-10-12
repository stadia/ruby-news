# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

require "date"
require "open3"

module Quality
  # bin/rubycritic의 입력 검사. 이력 오류는 churn 0·1로, 경로 누락은 일부 파일 분석으로
  # 정상처럼 보일 수 있으므로(#1087), 분석 전에 실행 조건을 확인한다.
  module RubycriticRun
    CHURN_MONTHS = 6
    DATE_FORMAT = /\A\d{4}-\d{2}-\d{2}\z/

    class << self
      # RUBYCRITIC_CHURN_AFTER를 해석한다. 비어 있으면 최근 6개월이다. 값은 RubyCritic 안에서
      # 셸 문자열(--after='...')로 들어가므로 Date로 해석한 뒤 다시 찍은 값만 넘긴다.
      #: (String? value, ?today: Date) -> String
      def churn_after(value, today: Time.now.utc.to_date)
        value = value.to_s.strip
        return "#{(today << CHURN_MONTHS).iso8601} 00:00:00 +0000" if value.empty?

        date = parse_date(value)
        raise ArgumentError, "RUBYCRITIC_CHURN_AFTER is in the future: #{value}" if date > today
        raise ArgumentError, "RUBYCRITIC_CHURN_AFTER cannot be today: #{value}" if date == today

        "#{date.iso8601} 00:00:00 +0000"
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

      # churn은 git log로 센다. 얕은 클론에서는 전부 1로 퇴화한다.
      # worktree가 메인 저장소 안이면 상위 .git을 잘못 고르고, 밖이면 정상일 수도 있어 모두 거부한다.
      # 하위 디렉터리의 churn은 정상이나 bin/rubycritic이 ROOT로 chdir하는 실행 전제를 확인한다.
      #: (String root) -> Array[String]
      def git_errors(root)
        output, stderr, status = Open3.capture3("git", "-C", root, "rev-parse", "--is-shallow-repository",
                                         "--show-toplevel", "--absolute-git-dir", "--path-format=absolute",
                                         "--git-common-dir")
        return [ "git rev-parse failed (#{status.exitstatus}): #{stderr.strip}" ] unless status.success?
        fields = output.lines.map(&:chomp)
        unless fields.size == 4 && %w[true false].include?(fields.first)
          return [ "unexpected git rev-parse output: #{output.inspect}; #{stderr.strip}" ]
        end

        shallow, toplevel, git_dir, common_dir = fields
        errors = []
        errors << "shallow clone: churn needs full history (fetch-depth: 0; git fetch --unshallow)" if shallow == "true"
        errors << "git worktree: run in a regular clone (churn depends on worktree location)" if git_dir != common_dir
        errors << "#{root} is not the git top level (#{toplevel})" unless same_path?(toplevel, root)
        errors
      rescue Errno::ENOENT
        [ "git not found on PATH" ]
      end

      #: (String? left, String right) -> bool
      def same_path?(left, right)
        !left.nil? && File.realpath(left) == File.realpath(right)
      end
    end
  end
end
