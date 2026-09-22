# typed: true
# frozen_string_literal: true

module RubyUI
  class InlineLink < Base
    def initialize(href:, **attrs)
      super(**attrs)
      @href = href
    end

    def view_template(&)
      a(href: @href, **attrs, &)
    end

    private

    def default_attrs
      {
        class: "text-link font-medium hover:text-link-hover hover:underline underline-offset-4 cursor-pointer"
      }
    end
  end
end
