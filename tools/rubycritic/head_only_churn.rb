# typed: false
# frozen_string_literal: true
# rbs_inline: disabled

# RubyCritic 5.0 churn은 `git log --all`이라 미병합 로컬 브랜치·remote ref의 커밋까지 센다.
# 같은 커밋에서 같은 값이 나오도록 HEAD 조상만 센다. bin/rubycritic이 RUBYOPT로 불러온다.
require "rubycritic/source_control_systems/base"
require "rubycritic/source_control_systems/git"

RubyCritic::SourceControlSystem::Git::Churn.prepend(Module.new do
  private

  def git_log_command(path)
    command = super
    # 명령 모양이 바뀌면(업그레이드) 조용히 --all로 돌지 않게 멈춘다.
    raise "RubyCritic churn 명령이 바뀌었다: #{command}" unless command.start_with?("log --all ")

    command.sub("log --all ", "log HEAD ")
  end
end)
