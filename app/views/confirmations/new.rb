# typed: true
# frozen_string_literal: true

class Views::Confirmations::New < Views::Base
  include Phlex::Rails::Helpers::ContentFor
  include Phlex::Rails::Helpers::FormWith

  def initialize(user:)
    @user = user
  end

  def view_template
    div(class: "mx-auto md:w-2/3 w-full") do
      render RubyUI::Heading.new(level: 1, class: "font-bold") { t("devise.confirmations.new.title") }

      form_with(model: @user, url: user_confirmation_path, scope: :user, class: "contents") do |f|
        if @user.errors.any?
          div(id: "error_explanation", class: "mb-6 rounded-xl border border-danger-solid/20 bg-danger-solid/10 p-4 text-danger-text") do
            h2(class: "mb-2 font-bold") { t("errors.messages.form_errors", count: @user.errors.count) }
            ul(class: "ml-6 list-disc space-y-1 text-sm") do
              @user.errors.each { |error| li { error.full_message } }
            end
          end
        end

        render RubyUI::FormField.new(class: "my-5") do
          render RubyUI::FormFieldLabel.new(for: :user_email) { t("activerecord.attributes.user.email") }
          f.email_field :email,
            required: true,
            autofocus: true,
            autocomplete: "email",
            placeholder: t("devise.confirmations.new.email_placeholder"),
            class: input_classes(@user.errors[:email])
          @user.errors[:email].each do |msg|
            render RubyUI::FormFieldError.new { msg }
          end
        end

        div(class: "inline") do
          render RubyUI::Button.new(
            type: "submit",
            variant: :primary,
            size: :lg,
            class: "w-full sm:w-auto rounded-md bg-brand-solid hover:bg-brand-solid-hover text-brand-foreground inline-block font-medium cursor-pointer focus:outline-none focus:ring-2 focus:ring-brand focus:ring-offset-2 focus:ring-offset-app"
          ) { t("devise.confirmations.new.submit") }
        end
      end
    end
  end

  private

  def input_classes(errors)
    base_classes = "mt-2 block w-full rounded-md border px-3 py-2 shadow-sm transition-colors duration-200 focus:outline-none focus:ring-2"
    error_classes = errors.any? ? "border-danger-text bg-app text-content focus:border-danger-text focus:ring-destructive/30" : "border-input bg-app text-content placeholder:text-content-muted focus:border-transparent focus:ring-brand"
    "#{base_classes} #{error_classes}"
  end
end
