# typed: false
# frozen_string_literal: true
# rbs_inline: disabled

# head_only_churn.rb 패치 테스트. RubyCritic 젬이 필요하므로 앱 테스트 스위트(Rails·앱 번들)가
# 아니라 tools/rubycritic 번들로 돈다. CI의 rubycritic 잡이 실행한다.
#
#   BUNDLE_GEMFILE=tools/rubycritic/Gemfile bundle exec ruby tools/rubycritic/test/head_only_churn_test.rb

require "bundler"
require "date"
require "fileutils"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"
require_relative "../../../lib/quality/rubycritic_run"

module Quality
  class HeadOnlyChurnTest < Minitest::Test
    ROOT = File.expand_path("../../..", __dir__)

    def test_일부_분석_경로의_git_log_실패도_명령과_종료_상태를_알린다
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

        refute_predicate status, :success?
        assert_empty stdout
        assert_includes stderr, "app/models"
        assert_includes stderr, "42"
        assert_includes stderr, "forced models log failure"
      end
    end

    def test_UTC_자정_이후의_경계일_커밋을_시차와_무관하게_센다
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
        require #{File.join(ROOT, 'tools/rubycritic/head_only_churn.rb').inspect}
        churn = RubyCritic::SourceControlSystem::Git::Churn.new(
          churn_after: #{RubycriticRun.churn_after('2026-10-11', today: Date.new(2026, 10, 12)).inspect},
          paths: ['app/models', 'app/services'])
        puts ['app/models/a.rb', 'app/services/a.rb'].map { churn.revisions_count(it) }.join(',')
      SCRIPT
      Bundler.with_unbundled_env do
        Open3.capture3(env.merge("BUNDLE_GEMFILE" => File.join(ROOT, "tools/rubycritic/Gemfile")),
          "bundle", "exec", RbConfig.ruby, "-e", script, chdir: repo)
      end
    end
  end
end
