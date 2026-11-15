# frozen_string_literal: true

require "test_helper"
require "open3"

# upstream tests/test_run_dir_resolution.py(v2.3.2)의 Ruby 포트 + sanitize 연동.
# 회귀를 잡으려면 반드시 저장소 밖 cwd에서 돌려야 한다.
class HumanizeKoreanPrepareMonolithInputTest < ActiveSupport::TestCase
  SHIM = Rails.root.join("app/skills/humanize-korean/scripts/prepare_monolith_input.rb").to_s
  SKILL_DIR = Rails.root.join("app/skills/humanize-korean")
  SAMPLE = "이것은 시험용 문장입니다. 첫째, 확인이 필요합니다. 둘째, 검증이 필요합니다."

  def run_shim(*args, cwd:)
    Open3.capture3(RbConfig.ruby, SHIM, *args, chdir: cwd)
  end

  def with_run_dir(name = "2026-08-17-001", text: SAMPLE)
    Dir.mktmpdir do |work|
      run = File.join(work, "_workspace", name)
      FileUtils.mkdir_p(run)
      File.write(File.join(run, "01_input.txt"), text, encoding: "UTF-8")
      yield work, run
    end
  end

  test "상대 --run-dir은 cwd 기준으로 푼다" do
    with_run_dir do |work, run|
      stdout, stderr, status = run_shim("--run-dir", "_workspace/2026-08-17-001", cwd: work)

      assert_predicate status, :success?, stderr
      assert File.file?(File.join(run, "01_input_with_metrics.txt"))
      assert_includes stdout, File.realpath(run)
    end
  end

  test "없는 run-dir은 만들지 않고 실패한다" do
    Dir.mktmpdir do |work|
      _stdout, _stderr, status = run_shim("--run-dir", "_workspace/missing", cwd: work)

      assert_not status.success?
      assert_not File.exist?(File.join(work, "_workspace", "missing"))
      assert_not SKILL_DIR.join("_workspace", "missing").exist?
    end
  end

  test "--text는 cwd 아래에 새 run 디렉터리를 만든다" do
    Dir.mktmpdir do |work|
      _stdout, stderr, status = run_shim("--text", SAMPLE, cwd: work)

      assert_predicate status, :success?, stderr
      assert_equal 1, Dir.glob(File.join(work, "_workspace", "*", "01_input_with_metrics.txt")).size
    end
  end

  test "상대 --diagnosis도 cwd 기준으로 푼다" do
    with_run_dir("2026-08-17-002") do |work, run|
      File.write(File.join(work, "diag.md"), "진단 메모", encoding: "UTF-8")
      _stdout, stderr, status = run_shim("--run-dir", "_workspace/2026-08-17-002", "--diagnosis", "diag.md", cwd: work)

      assert_predicate status, :success?, stderr
      assert_includes File.read(File.join(run, "01_input_with_metrics.txt"), encoding: "UTF-8"), "진단 메모"
    end
  end

  test "입력을 위생 처리해 01_input.txt에 반영하고 보고서를 남긴다" do
    with_run_dir(text: SAMPLE.unicode_normalize(:nfd)) do |work, run|
      stdout, stderr, status = run_shim("--run-dir", "_workspace/2026-08-17-001", cwd: work)

      assert_predicate status, :success?, stderr
      assert_equal SAMPLE, File.read(File.join(run, "01_input.txt"), encoding: "UTF-8")
      assert File.file?(File.join(run, "00_sanitize.json"))
      assert_match(/^sanitize=/, stdout)
    end
  end

  # 위생 처리 실패는 파이프라인을 막지 않지만, 정규화되지 않은 기준선이 남으므로 흔적을 남긴다.
  test "위생 처리가 실패하면 원문으로 계속하되 증적과 경고를 남긴다" do
    with_run_dir("2026-08-17-003") do |work, run|
      script = <<~RUBY
        load #{SHIM.dump}
        HumanizeKoreanSanitize.define_singleton_method(:sanitize) { |*| raise "boom" }
        exit main(["--run-dir", "_workspace/2026-08-17-003"])
      RUBY
      _stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-e", script, chdir: work)

      assert_predicate status, :success?, stderr
      assert_equal SAMPLE, File.read(File.join(run, "01_input.txt"), encoding: "UTF-8")
      assert_match(/sanitize_failed: RuntimeError: boom/, File.read(File.join(run, "00_sanitize.error")))
      assert_match(/sanitize_failed/, stderr)
    end
  end

  test "--no-sanitize면 입력을 그대로 둔다" do
    nfd = SAMPLE.unicode_normalize(:nfd)
    with_run_dir(text: nfd) do |work, run|
      _stdout, stderr, status = run_shim("--run-dir", "_workspace/2026-08-17-001", "--no-sanitize", cwd: work)

      assert_predicate status, :success?, stderr
      assert_equal nfd, File.read(File.join(run, "01_input.txt"), encoding: "UTF-8")
      assert_not File.exist?(File.join(run, "00_sanitize.json"))
    end
  end
end
