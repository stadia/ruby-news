# frozen_string_literal: true

require "test_helper"
require Rails.root.join("app/skills/humanize-korean/scripts/verify_gates").to_s

class HumanizeKoreanVerifyGatesTest < ActiveSupport::TestCase
  # 처리되지 않은 예외는 Ruby도 exit 1로 끝나는데, 게이트 계약에서 1은 "경고"다.
  # 검증이 죽은 것이 경고로 읽히지 않도록 3(실행 오류)으로 보낸다. (upstream #84)
  test "예상치 못한 예외는 실행 오류 코드 3으로 보낸다" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "text.txt")
      File.write(path, "문장입니다.", encoding: "UTF-8")

      code = nil
      HumanizeKoreanVerifyGates.stub(:strip_summary_block, ->(*) { raise "boom" }) do
        _out, err = capture_io { code = HumanizeKoreanVerifyGates.run_gate([ "--before", path, "--after", path ]) }

        assert_includes err, "[gate] 실행 오류 — RuntimeError: boom"
      end

      assert_equal 3, code
    end
  end
end
