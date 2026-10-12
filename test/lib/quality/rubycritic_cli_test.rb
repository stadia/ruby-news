# frozen_string_literal: true

require "test_helper"
require "open3"
require "rbconfig"

module Quality
  class RubycriticCliTest < ActiveSupport::TestCase
    test "분석 실패 시 이전 HTML과 JSON을 지우고 요약을 출력하지 않는다" do
      in_cli_repo do |repo, env|
        output = File.join(repo, "tmp/rubycritic")
        FileUtils.mkdir_p(output)
        %w[report.json overview.html].each { File.write(File.join(output, it), "stale") }
        fake_bundle(repo, "echo failed >&2; exit 7")
        stdout, stderr, status = run_cli(repo, env)

        assert_equal 1, status.exitstatus
        assert_empty stdout
        assert_includes stderr, "Install the bundle"
        assert_not File.exist?(File.join(output, "report.json"))
        assert_not File.exist?(File.join(output, "overview.html"))
      end
    end

    test "날짜가 잘못되면 분석을 실행하지 않는다" do
      in_cli_repo do |repo, env|
        fake_bundle(repo, "touch called; exit 0")
        stdout, stderr, status = run_cli(repo, env.merge("RUBYCRITIC_CHURN_AFTER" => "garbage"))

        assert_equal 1, status.exitstatus
        assert_empty stdout
        assert_match(/YYYY-MM-DD/, stderr)
        assert_not File.exist?(File.join(repo, "called"))
      end
    end

    test "리포트 누락과 잘못된 JSON은 예외 클래스와 함께 실패한다" do
      [ [ "exit 0", "Errno::ENOENT" ], [ "mkdir -p tmp/rubycritic; echo broken > tmp/rubycritic/report.json", "JSON::ParserError" ] ].each do |script, error_class|
        in_cli_repo do |repo, env|
          fake_bundle(repo, script)
          stdout, stderr, status = run_cli(repo, env)

          assert_equal 1, status.exitstatus
          assert_empty stdout
          assert_includes stderr, "rubycritic report is not usable"
          assert_includes stderr, error_class
          assert_not_includes stderr, "from bin/rubycritic"
        end
      end
    end

    private

    def in_cli_repo
      Dir.mktmpdir do |repo|
        %w[bin lib/quality tools/rubycritic app/models app/controllers app/services app/functions app/clients].each do |dir|
          FileUtils.mkdir_p(File.join(repo, dir))
        end
        %w[bin/rubycritic lib/quality/rubycritic_run.rb lib/quality/rubycritic_report.rb].each do |file|
          FileUtils.cp(Rails.root.join(file), File.join(repo, file))
        end
        env = { "GIT_CONFIG_GLOBAL" => "/dev/null", "GIT_CONFIG_NOSYSTEM" => "1", "GIT_DIR" => nil,
                "GIT_INDEX_FILE" => nil, "GIT_WORK_TREE" => nil, "RUBYOPT" => nil,
                "PATH" => "#{repo}/fake-bin:#{ENV.fetch('PATH')}" }
        _stdout, stderr, status = Open3.capture3(env, "git", "init", "-q", repo)
        raise stderr unless status.success?

        yield repo, env
      end
    end

    def fake_bundle(repo, script)
      dir = File.join(repo, "fake-bin")
      FileUtils.mkdir_p(dir)
      path = File.join(dir, "bundle")
      File.write(path, "#!/bin/sh\n#{script}\n")
      FileUtils.chmod(0o755, path)
    end

    def run_cli(repo, env)
      # 앱 Bundler 환경은 자식에 전달하지 않는다. 가짜 bundle은 shell이라 RUBYOPT를 읽지 않는다.
      Bundler.with_unbundled_env do
        Open3.capture3(env, RbConfig.ruby, "bin/rubycritic", chdir: repo)
      end
    end
  end
end
