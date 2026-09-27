# typed: true
# frozen_string_literal: true

class Views::Passwords::New < Views::Base
  include Phlex::Rails::Helpers::ContentFor
  include Phlex::Rails::Helpers::FormWith
  include Phlex::Rails::Helpers::Request

  def view_template
    div(class: "mx-auto md:w-2/3 w-full") do
      render RubyUI::Heading.new(level: 1, class: "font-bold") { t("passwords.new.heading") }

      form_with(url: user_password_path, scope: :user, class: "contents") do |f|
        render RubyUI::FormField.new(class: "my-5") do
          render RubyUI::FormFieldLabel.new(for: :email) { User.human_attribute_name(:email) }
          f.email_field :email,
            required: true,
            autofocus: true,
            autocomplete: "username",
            placeholder: t("helpers.placeholder.user.email"),
            value: request.params[:email],
            class: "block shadow-sm rounded-md border border-input px-3 py-2 mt-2 w-full bg-app text-content placeholder:text-content-muted focus:outline-none focus:ring-2 focus:ring-brand focus:border-transparent transition-colors duration-200"
        end

        div(class: "inline") do
          render RubyUI::Button.new(
            type: "submit",
            variant: :primary,
            size: :lg,
            class: "w-full sm:w-auto rounded-md bg-brand-solid hover:bg-brand-solid-hover text-brand-foreground inline-block font-medium cursor-pointer focus:outline-none focus:ring-2 focus:ring-brand focus:ring-offset-2 focus:ring-offset-app"
          ) { t("passwords.new.submit") }
        end
      end
    end
  end
end
