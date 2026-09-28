# typed: false
# frozen_string_literal: true

# PostgreSQL이나 Rails를 부팅하지 않고 실제 프로세스 사이의 잠금을 검증한다.
require "minitest/autorun"
require "json"
require "open3"
require "securerandom"
require "timeout"
require "tmpdir"

class TestDatabaseGuardTest < Minitest::Test
  GUARD_PATH = File.expand_path("../support/test_database_guard.rb", __dir__)
  RUNNER = <<~RUBY
    require "json"
    require "timeout"
    require ARGV.fetch(0)
    original_url = ENV["TEST_DATABASE_URL"]
    Timeout.timeout(5) do
      TestDatabaseGuard.acquire!(JSON.parse(ARGV.fetch(1), symbolize_names: true))
    end
    abort "TEST_DATABASE_URL changed" unless ENV["TEST_DATABASE_URL"] == original_url
    GC.start
    puts "locked"
    STDOUT.flush
    STDIN.gets if ARGV.fetch(2) == "hold"
  RUBY
  COVERAGE_RUNNER = <<~RUBY + RUNNER
    require "simplecov"
    require "pathname"
    require ARGV.fetch(4)
    SimpleCov.root(ARGV.fetch(3))
    SimpleCov.coverage_dir("coverage")
    SimpleCov.start { enable_coverage :branch }
    SimpleCov.command_name "Guard regression"
    SimpleCov.at_exit do
      result = SimpleCov.result
      result.format!
      Quality::CoverageSnapshot.persist_result!(result, Pathname.new(ARGV.fetch(3)))
    end
  RUBY

  def setup
    @configuration = { host: "localhost", port: 5432, database: "guard_test_#{SecureRandom.hex(12)}" }
  end

  def test_same_database_rejects_second_process_without_exposing_credentials
    with_holder(@configuration.merge(username: "first_user")) do
      output, status = run_guard(@configuration.merge(username: "second_user", password: "private_password"))

      refute_predicate status, :success?
      assert_includes output, "TEST_DATABASE_URL"
      assert_includes output, "다른 테스트 프로세스"
      refute_includes output, "private_password"
      refute_includes output, "second_user"
      refute_includes output, @configuration.fetch(:database)
    end
  end

  def test_different_database_allows_concurrent_process
    with_holder(@configuration) do
      output, status = run_guard(@configuration.merge(database: "#{@configuration.fetch(:database)}_other"))

      assert_predicate status, :success?, output
      assert_includes output, "locked"
    end
  end

  def test_default_host_and_port_share_the_explicit_local_database_lock
    with_holder(@configuration.except(:host, :port)) do
      output, status = run_guard(@configuration.merge(port: "5432"))

      refute_predicate status, :success?, output
      assert_includes output, "다른 테스트 프로세스"
    end
  end

  def test_process_exit_releases_database_lock
    with_holder(@configuration) { }
    output, status = run_guard(@configuration)

    assert_predicate status, :success?, output
  end

  def test_different_working_directories_share_the_database_lock
    with_holder(@configuration, chdir: File.expand_path("../..", __dir__)) do
      output, status = run_guard(@configuration, chdir: Dir.tmpdir)

      refute_predicate status, :success?, output
      assert_includes output, "다른 테스트 프로세스"
    end
  end

  def test_rejected_runner_preserves_existing_coverage_files
    with_holder(@configuration) do
      Dir.mktmpdir do |directory|
        paths = seed_coverage(directory)
        previous_contents = paths.to_h { |path| [ path, File.read(path) ] }
        output, status = run_coverage_guard(directory)

        refute_predicate status, :success?, output
        assert_includes output, "다른 테스트 프로세스"
        paths.each { |path| assert_equal previous_contents.fetch(path), File.read(path), path }
      end
    end
  end

  def test_accepted_runner_still_records_coverage
    Dir.mktmpdir do |directory|
      paths = seed_coverage(directory)
      output, status = run_coverage_guard(directory)

      assert_predicate status, :success?, output
      assert JSON.parse(File.read(paths.first)).key?("Guard regression")
      assert JSON.parse(File.read(paths.last)).fetch("result").key?("branch")
      refute_equal 99, JSON.parse(File.read(paths.last)).fetch("result").fetch("line")
    end
  end

  private

  def seed_coverage(directory)
    coverage = File.join(directory, "coverage")
    Dir.mkdir(coverage)
    %w[.resultset.json .last_run.json .quality_last_run.json].map do |name|
      path = File.join(coverage, name)
      File.write(path, name == ".resultset.json" ? "{}" : '{"result":{"line":99,"branch":99}}')
      path
    end
  end

  def run_coverage_guard(directory)
    snapshot = File.expand_path("../../lib/quality/coverage_snapshot.rb", __dir__)
    Open3.capture2e(RbConfig.ruby, "-e", COVERAGE_RUNNER, GUARD_PATH, JSON.generate(@configuration), "once", directory, snapshot, chdir: directory)
  end

  def run_guard(configuration, **options)
    Open3.capture2e(RbConfig.ruby, "-e", RUNNER, GUARD_PATH, JSON.generate(configuration), "once", **options)
  end

  def with_holder(configuration, **options)
    Open3.popen2e(RbConfig.ruby, "-e", RUNNER, GUARD_PATH, JSON.generate(configuration), "hold", **options) do |input, output, waiter|
      assert_equal "locked\n", Timeout.timeout(10) { output.gets }
      yield
    ensure
      input.close
      Timeout.timeout(10) { waiter.value }
    end
  end
end
