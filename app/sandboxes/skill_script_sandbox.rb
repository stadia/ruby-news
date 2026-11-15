# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

# 스킬 스크립트를 실행하는 샌드박스. 기사 본문에서 온 프롬프트가 실행할 코드를 고를 수 있으므로
# 네트워크와 앱 파일 접근 없이, RubyLLM이 열어 주는 실행 디렉터리와 읽기 전용 스킬 마운트만 허용한다.
class SkillScriptSandbox < MXC::Sandbox
  network false
  timeout 60
  # Landlock은 파일·네트워크만 격리하므로 폭주하는 스크립트가 워커를 잡아먹지 않게 자원을 제한한다.
  limits cpu_time: 60
  # macOS(Seatbelt)는 메모리 제한을 지원하지 않아(MXC::UnsupportedError) 운영 환경인 Linux에서만 건다.
  limits memory: 512 * 1024**2 if RUBY_PLATFORM.include?("linux")
end
