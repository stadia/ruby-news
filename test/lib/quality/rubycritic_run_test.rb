# frozen_string_literal: true

require "test_helper"
require "open3"
require_relative "../../../lib/quality/rubycritic_run"

module Quality
  class RubycriticRunTest < ActiveSupport::TestCase
    TODAY = Date.new(2026, 10, 12)

    test "churn 시작일이 없거나 비어 있으면 6개월 전으로 둔다" do
      assert_equal "2026-04-12", RubycriticRun.churn_after(nil, today: TODAY)
      assert_equal "2026-04-12", RubycriticRun.churn_after("  ", today: TODAY)
    end

    test "churn 시작일은 ISO 8601 날짜를 받아 YYYY-MM-DD로 돌려준다" do
      assert_equal "2026-04-11", RubycriticRun.churn_after("2026-04-11", today: TODAY)
      assert_equal "2026-04-11", RubycriticRun.churn_after(" 2026-04-11 ", today: TODAY)
    end

    # 값은 RubyCritic 안에서 셸 문자열(--after='...')로 들어가므로 날짜가 아닌 문자는 거부한다.
    test "날짜가 아니거나 미래인 churn 시작일은 거부한다" do
      [ "garbage", "2026-13-01", "2026-04-11'; rm -rf /'", "2026-10-13" ].each do |value|
        error = assert_raises(ArgumentError, value) { RubycriticRun.churn_after(value, today: TODAY) }
        assert_includes error.message, "RUBYCRITIC_CHURN_AFTER", value
      end
    end

    # Date.iso8601은 주 단위(2026-W15-6)·구분자 없는 날짜도 받지만, 문서 계약은 YYYY-MM-DD다.
    test "YYYY-MM-DD가 아닌 ISO 8601 표기는 거부한다" do
      [ "2026-W15-6", "20260411" ].each do |value|
        assert_raises(ArgumentError, value) { RubycriticRun.churn_after(value, today: TODAY) }
      end
    end

    test "오늘 날짜는 churn 시작일로 받는다" do
      assert_equal "2026-10-12", RubycriticRun.churn_after("2026-10-12", today: TODAY)
    end

    test "일반 클론에 분석 디렉터리가 모두 있으면 사전 검사를 통과한다" do
      in_repo do |repo|
        assert_empty RubycriticRun.preflight_errors(root: repo, paths: %w[app])
      end
    end

    test "없는 분석 디렉터리를 알린다" do
      in_repo do |repo|
        errors = RubycriticRun.preflight_errors(root: repo, paths: %w[app lib missing])

        assert_equal 1, errors.size
        assert_includes errors.first, "lib, missing"
      end
    end

    # 얕은 클론이면 churn이 전부 1이 되어 순위가 복잡도 단독으로 퇴화한다.
    test "얕은 클론을 거부한다" do
      in_repo do |repo|
        clone = File.join(File.dirname(repo), "shallow")
        git!(File.dirname(repo), "clone", "-q", "--depth", "1", "file://#{repo}", clone)

        assert_match(/shallow/, RubycriticRun.preflight_errors(root: clone, paths: %w[app]).join)
      end
    end

    # RubyCritic은 .git 디렉터리를 찾아 올라가 상위 저장소를 루트로 잡아 churn이 전부 0이 된다.
    test "git 작업 트리를 거부한다" do
      in_repo do |repo|
        worktree = File.join(File.dirname(repo), "wt")
        git!(repo, "worktree", "add", "-q", worktree)

        assert_match(/worktree/, RubycriticRun.preflight_errors(root: worktree, paths: %w[app]).join)
      end
    end

    test "git 저장소가 아니면 거부한다" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "app"))

        assert_match(/git/, RubycriticRun.preflight_errors(root: dir, paths: %w[app]).join)
      end
    end

    private

    def in_repo
      Dir.mktmpdir do |dir|
        repo = File.join(dir, "repo")
        FileUtils.mkdir_p(File.join(repo, "app"))
        File.write(File.join(repo, "app", "a.rb"), "1\n")
        git!(repo, "init", "-q")
        git!(repo, "add", ".")
        git!(repo, "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "-m", "init")
        yield repo
      end
    end

    def git!(dir, *args)
      output, status = Open3.capture2e("git", "-C", dir, *args)
      raise "git #{args.join(" ")} failed: #{output}" unless status.success?
    end
  end
end
