# typed: false
# frozen_string_literal: true
# rbs_inline: disabled

# RubyCritic 5.0 churn은 `git log --all`이라 미병합 로컬 브랜치·remote ref의 커밋까지 센다.
# 같은 커밋에서 같은 값이 나오도록 HEAD 조상만 센다. bin/rubycritic이 RUBYOPT로 불러온다.
require "open3"
require "shellwords"
require "rubycritic/source_control_systems/base"
require "rubycritic/source_control_systems/git"

RubyCritic::SourceControlSystem::Git::Churn.prepend(Module.new do
  private

  # 업스트림은 git 종료 상태를 무시하므로 한 경로의 실패도 churn 0으로 묻힌다.
  def exec_git_command(command)
    output, stderr, status = Open3.capture3(RubyCritic::SourceControlSystem::Git::GIT_EXECUTABLE,
      *Shellwords.split(command), chdir: @git_root)
    unless status.success?
      raise "RubyCritic git command failed (exit #{status.exitstatus}): #{command}; #{stderr.strip}"
    end

    output.lines.map(&:chomp).reject(&:empty?).each { |line| process_line(line) }
  end

  def git_log_command(path)
    command = super
    # 명령 모양이 바뀌면(업그레이드) 조용히 --all로 돌지 않게 멈춘다.
    raise "RubyCritic churn 명령이 바뀌었다: #{command}" unless command.start_with?("log --all ")

    command.sub("log --all ", "log HEAD ")
  end
end)
