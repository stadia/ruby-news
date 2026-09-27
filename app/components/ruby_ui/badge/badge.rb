# typed: true
# frozen_string_literal: true

module RubyUI
  class Badge < Base
    SIZES = {
      sm: "px-1.5 py-0.5 text-xs",
      md: "px-2 py-1 text-xs",
      lg: "px-3 py-1 text-sm"
    }

    COLORS = {
      primary: "text-accent-text bg-brand/10 ring-brand/20",
      secondary: "text-content-secondary bg-surface-muted ring-border-muted",
      outline: "text-content bg-surface ring-border-strong",
      destructive: "text-danger-text bg-danger-solid/10 ring-danger-solid/20",
      success: "text-success-text bg-success/10 ring-success/20",
      warning: "text-warning-text bg-warning/10 ring-warning/20",
      slate: "text-content-secondary bg-surface-muted ring-border-muted",
      gray: "text-content-secondary bg-surface-muted ring-border-muted",
      zinc: "text-content-secondary bg-surface-muted ring-border-muted",
      neutral: "text-content-secondary bg-surface-muted ring-border-muted",
      stone: "text-content-secondary bg-surface-muted ring-border-muted",
      red: "text-danger-text bg-danger-solid/10 ring-danger-solid/20",
      orange: "text-warning-text bg-warning/10 ring-warning/20",
      amber: "text-warning-text bg-warning/10 ring-warning/20",
      yellow: "text-warning-text bg-warning/10 ring-warning/20",
      lime: "text-success-text bg-success/10 ring-success/20",
      green: "text-success-text bg-success/10 ring-success/20",
      emerald: "text-success-text bg-success/10 ring-success/20",
      teal: "text-success-text bg-success/10 ring-success/20",
      cyan: "text-info-text bg-info-solid/10 ring-info-solid/20",
      sky: "text-info-text bg-info-solid/10 ring-info-solid/20",
      blue: "text-info-text bg-info-solid/10 ring-info-solid/20",
      indigo: "text-info-text bg-info-solid/10 ring-info-solid/20",
      violet: "text-accent-text bg-brand/10 ring-brand/20",
      purple: "text-accent-text bg-brand/10 ring-brand/20",
      fuchsia: "text-accent-text bg-brand/10 ring-brand/20",
      pink: "text-accent-text bg-brand/10 ring-brand/20",
      rose: "text-accent-text bg-brand/10 ring-brand/20"
    }

    def initialize(variant: :primary, size: :md, **args)
      @variant = variant
      @size = size
      super(**args)
    end

    def view_template(&)
      span(**attrs, &)
    end

    private

    def default_attrs
      {
        class: ["inline-flex items-center rounded-md font-medium ring-1 ring-inset", SIZES[@size], COLORS[@variant]]
      }
    end
  end
end
