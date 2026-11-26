# typed: false
# frozen_string_literal: true
# rbs_inline: enabled

# `bin/tapioca gem`이 앱을 부팅하는 동안 tapioca 0.20.0의 RBS 리라이터가 herb·reactionview 소스의 `#:` 주석을
# sig로 바꾸다 깨진다(RBI::ParseError, Boolish NameError). 리라이터는 Spoom::Sorbet::Translate::Error만 rescue한다.
# 두 젬은 원본 소스를 그대로 쓰게 한다. RUBYOPT로만 싣는다(.github/workflows/dependabot-rbi.yml 참고):
#   RUBYOPT="-r$PWD/sorbet/tapioca/skip_broken_rbs_rewrite.rb" bin/tapioca gem
# `require "spoom"`을 하면 spoom RBI의 pkg:gem 위치 주석이 사라지므로, Translate가 정의되는 순간 prepend한다.
# shortcut: upstream이 고쳐지면 이 파일과 워크플로의 RUBYOPT를 지운다.
module SkipBrokenRbsRewrite
  def rbs_comments_to_sorbet_sigs(source, file:, **kw)
    return source if file.to_s.match?(%r{/gems/(herb|reactionview)-})

    super
  end
end

class Module
  prepend(Module.new do
    def const_added(name)
      super
      # rubocop가 Module#name을 재정의해 원래 메서드를 직접 묶는다.
      full = Module.instance_method(:name).bind_call(self)
      Spoom::Sorbet::Translate.singleton_class.prepend(SkipBrokenRbsRewrite) if full == "Spoom::Sorbet" && name == :Translate
    end
  end)
end
