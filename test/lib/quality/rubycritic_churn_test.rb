# frozen_string_literal: true

require "test_helper"
require "open3"
require "rbconfig"
require_relative "../../../lib/quality/rubycritic_run"

module Quality
  class RubycriticChurnTest < ActiveSupport::TestCase
    test "일부 분석 경로의 git log 실패도 명령과 종료 상태를 알린다" do
      in_repo do |repo, env|
        fake = File.join(repo, "fake-bin")
        FileUtils.mkdir_p(fake)
        real_git, = Open3.capture2("which", "git")
        File.write(File.join(fake, "git"), <<~SCRIPT)
          #!#{RbConfig.ruby}
          if ARGV.first == "log" && ARGV.last == "app/models"
            warn "forced models log failure"
            exit 42
          end
          exec ENV.fetch("REAL_GIT"), *ARGV
        SCRIPT
        FileUtils.chmod(0o755, File.join(fake, "git"))
        stdout, stderr, status = churn(repo, env.merge("PATH" => "#{fake}:#{ENV.fetch('PATH')}", "REAL_GIT" => real_git.strip))

        assert_not status.success?
        assert_empty stdout
        assert_includes stderr, "app/models"
        assert_includes stderr, "42"
        assert_includes stderr, "forced models log failure"
      end
    end

    test "UTC 자정 이후의 경계일 커밋을 시차와 무관하게 센다" do
      in_repo do |repo, env|
        stdout, stderr, status = churn(repo, env.merge("TZ" => "Asia/Seoul"))

        assert_predicate status, :success?, stderr
        assert_equal "1,1\n", stdout
      end
    end

    private

    def in_repo
      Dir.mktmpdir do |repo|
        %w[app/models app/services].each do |dir|
          FileUtils.mkdir_p(File.join(repo, dir))
          File.write(File.join(repo, dir, "a.rb"), "puts 1\n")
        end
        env = { "GIT_CONFIG_GLOBAL" => "/dev/null", "GIT_CONFIG_NOSYSTEM" => "1", "GIT_DIR" => nil,
                "GIT_INDEX_FILE" => nil, "GIT_WORK_TREE" => nil, "RUBYOPT" => nil,
                "GIT_AUTHOR_DATE" => "2026-10-11T00:01:00+0000", "GIT_COMMITTER_DATE" => "2026-10-11T00:01:00+0000" }
        [ %w[init -q], %w[add .], %w[-c user.name=t -c user.email=t@example.com commit -q -m init] ].each do |args|
          _stdout, stderr, status = Open3.capture3(env, "git", *args, chdir: repo)
          raise stderr unless status.success?
        end
        yield repo, env
      end
    end

    def churn(repo, env)
      script = <<~SCRIPT
        require #{Rails.root.join('tools/rubycritic/head_only_churn.rb').to_s.inspect}
        churn = RubyCritic::SourceControlSystem::Git::Churn.new(
          churn_after: #{RubycriticRun.churn_after('2026-10-11', today: Date.new(2026, 10, 12)).inspect},
          paths: ['app/models', 'app/services'])
        puts ['app/models/a.rb', 'app/services/a.rb'].map { churn.revisions_count(it) }.join(',')
      SCRIPT
      Bundler.with_unbundled_env do
        Open3.capture3(env.merge("BUNDLE_GEMFILE" => Rails.root.join("tools/rubycritic/Gemfile").to_s),
          "bundle", "exec", RbConfig.ruby, "-e", script, chdir: repo)
      end
    end
  end
end
