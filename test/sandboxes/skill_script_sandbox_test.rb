# frozen_string_literal: true

require "test_helper"

class SkillScriptSandboxTest < ActiveSupport::TestCase
  # Landlock은 파일·네트워크만 격리하므로 폭주하는 스크립트는 자원 제한으로 막는다.
  test "CPU 시간을 제한하고 네트워크를 막는다" do
    sandbox = SkillScriptSandbox.new

    assert_equal 60, sandbox.limits[:cpu_time]
    assert_not sandbox.network
  end

  test "메모리 제한은 지원되는 Linux에서만 건다" do
    memory = SkillScriptSandbox.new.limits[:memory]

    if RUBY_PLATFORM.include?("linux")
      assert_equal 512 * 1024**2, memory
    else
      assert_nil memory
    end
  end
end
