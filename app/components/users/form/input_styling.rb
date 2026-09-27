# typed: true
# frozen_string_literal: true

# users/form 필드 서브컴포넌트들이 공유하는 입력 필드 클래스 헬퍼.
# 중복 정의를 막기 위해 단일 모듈로 추출한다.
module Components::Users::Form::InputStyling
  private

  def input_classes(errors)
    base_classes = "block w-full bg-surface/50 border rounded-xl px-4 py-3 text-content placeholder:text-content-muted focus:outline-none focus:ring-2 transition-all duration-200"
    error_classes = errors.any? ? "border-danger-text focus:ring-destructive/30" : "border-input focus:ring-brand/30 focus:border-brand/50"
    "#{base_classes} #{error_classes}"
  end
end
