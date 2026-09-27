# typed: true
# app/views/actors/lookup.rb
# frozen_string_literal: true

class Views::Actors::Lookup < Views::Base
  include Phlex::Rails::Helpers::ContentFor

  def view_template
    content_for :title, t("actors.lookup.title")

    div(class: "max-w-xl mx-auto py-8") do
      render RubyUI::Heading.new(level: 1) { t("actors.lookup.heading") }
      p(class: "text-content-muted mt-2 mb-6") { t("actors.lookup.subtitle") }

      render RubyUI::Form.new(action: lookup_actors_url, method: :get, class: "flex gap-2 items-end") do
        render RubyUI::FormField.new(class: "flex-1") do
          render RubyUI::FormFieldLabel.new(for: "account", class: "text-content-secondary") { t("actors.lookup.account_label") }
          render RubyUI::Input.new(
            type: :text,
            name: "account",
            id: "account",
            placeholder: t("helpers.placeholder.actor.account"),
            required: true,
            autofocus: true,
            class: "bg-app border-input text-content placeholder:text-content-muted"
          )
        end
        render RubyUI::Button.new(type: "submit", class: "bg-brand-solid hover:bg-brand-solid-hover text-brand-foreground") { t("actors.lookup.submit") }
      end
    end
  end
end
