# typed: true
# frozen_string_literal: true

# 소개·약관·개인정보처리방침 같은 정적 문서 페이지의 제목 달린 단락.
class Components::Home::DocSection < Components::Base
  def initialize(title:)
    @title = title
  end

  def view_template(&)
    section(class: "space-y-4") do
      render RubyUI::Heading.new(level: 2, class: "font-semibold text-accent-text mb-3") { @title }
      yield
    end
  end
end
