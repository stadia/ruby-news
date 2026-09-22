# typed: true
# frozen_string_literal: true

module RubyUI
  class FormFieldError < Base
    def view_template(&)
      p(**attrs, &)
    end

    private

    def default_attrs
      {
        data: {
          ruby_ui__form_field_target: "error"
        },
        class: "empty:hidden text-sm font-medium text-danger-text"
      }
    end
  end
end
