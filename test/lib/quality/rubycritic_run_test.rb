# frozen_string_literal: true

require "test_helper"
require "open3"
require_relative "../../../lib/quality/rubycritic_run"

module Quality
  class RubycriticRunTest < ActiveSupport::TestCase
    TODAY = Date.new(2026, 10, 12)

    test "churn 시작일이 없거나 비어 있으면 6개월 전으로 둔다" do
      assert_equal "2026-04-12 00:00:00 +0000", RubycriticRun.churn_after(nil, today: TODAY)
      assert_equal "2026-04-12 00:00:00 +0000", RubycriticRun.churn_after("  ", today: TODAY)
    end

    test "churn 시작일은 ISO 8601 날짜를 받아 UTC 자정으로 돌려준다" do
      assert_equal "2026-04-11 00:00:00 +0000", RubycriticRun.churn_after("2026-04-11", today: TODAY)
      assert_equal "2026-04-11 00:00:00 +0000", RubycriticRun.churn_after(" 2026-04-11 ", today: TODAY)
    end

    # 값은 RubyCritic 안에서 셸 문자열(--after='...')로 들어가므로 날짜가 아닌 문자는 거부한다.
    test "날짜가 아니거나 미래인 churn 시작일은 거부한다" do
      [ "garbage", "2026-13-01", "2026-04-11'; rm -rf /'" ].each do |value|
        error = assert_raises(ArgumentError, value) { RubycriticRun.churn_after(value, today: TODAY) }
        assert_match(/YYYY-MM-DD/, error.message, value)
      end
    end

    # Date.iso8601은 주 단위(2026-W15-6)·구분자 없는 날짜도 받지만, 문서 계약은 YYYY-MM-DD다.
    test "YYYY-MM-DD가 아닌 ISO 8601 표기는 거부한다" do
      [ "2026-W15-6", "20260411" ].each do |value|
        assert_raises(ArgumentError, value) { RubycriticRun.churn_after(value, today: TODAY) }
      end
    end

    test "오늘 날짜는 완료되지 않은 churn 기간이라 거부한다" do
      error = assert_raises(ArgumentError) { RubycriticRun.churn_after("2026-10-12", today: TODAY) }
      assert_match(/today/, error.message)
    end

    test "저장소 하위 위치는 실행 루트 전제를 위반해 거부한다" do
      in_repo do |repo|
        errors = RubycriticRun.preflight_errors(root: File.join(repo, "app"), paths: %w[.])

        assert_equal 1, errors.size
        assert_match(/top level/, errors.first)
      end
    end

    test "git trace는 stdout 구문 분석을 방해하지 않는다" do
      in_repo do |repo|
        previous = ENV["GIT_TRACE"]
        ENV["GIT_TRACE"] = "1"

        assert_empty RubycriticRun.preflight_errors(root: repo, paths: %w[app])
      ensure
        ENV["GIT_TRACE"] = previous
      end
    end

    test "git 실행 파일이 없으면 사전 검사 메시지로 실패한다" do
      Open3.stub(:capture3, ->(*) { raise Errno::ENOENT, "git" }) do
        errors = RubycriticRun.preflight_errors(root: Dir.pwd, paths: %w[app])

        assert_match(/git not found on PATH/, errors.join)
      end
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

    # 저장소 밖 worktree는 churn이 정상이어도, 위치에 따른 결과 차이를 피하려고 모두 거부한다.
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

        errors = RubycriticRun.preflight_errors(root: dir, paths: %w[app])

        assert_equal 1, errors.size
        # git 메시지는 로케일에 따라 번역되므로(예: LANG=ko) 고정된 접두어와 종료 코드만 본다.
        assert_match(/\Agit rev-parse failed \(128\): fatal:/, errors.first)
      end
    end

    test "저장소 안에 만든 worktree도 거부한다" do
      in_repo do |repo|
        worktree = File.join(repo, "nested-worktree")
        git!(repo, "worktree", "add", "-q", worktree)

        assert_match(/worktree/, RubycriticRun.preflight_errors(root: worktree, paths: %w[app]).join)
      end
    end

    test "미래 churn 날짜는 형식 오류와 구분해서 알린다" do
      error = assert_raises(ArgumentError) { RubycriticRun.churn_after("2026-10-13", today: TODAY) }
      assert_match(/future/, error.message)
    end

    test "git 출력 줄 수가 계약과 다르면 경로로 해석하지 않는다" do
      _out, _err, status = Open3.capture3("git", "--version")
      Open3.stub(:capture3, ->(*) { [ "false\nshort\n", "warning", status ] }) do
        errors = RubycriticRun.preflight_errors(root: Dir.pwd, paths: %w[app])

        assert_equal 1, errors.size
        assert_match(/unexpected git rev-parse output/, errors.first)
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
      env = { "GIT_CONFIG_GLOBAL" => "/dev/null", "GIT_CONFIG_NOSYSTEM" => "1",
              "GIT_DIR" => nil, "GIT_INDEX_FILE" => nil, "GIT_WORK_TREE" => nil }
      output, status = Open3.capture2e(env, "git", "-C", dir, *args)
      raise "git #{args.join(" ")} failed: #{output}" unless status.success?
    end
  end
end
