# typed: true
# frozen_string_literal: true

class Views::Sessions::New < Views::Base
  include Phlex::Rails::Helpers::FormWith

  def view_template
    div(class: "space-y-6 max-w-6xl mx-auto") do
      render RubyUI::Heading.new(level: 1, class: "font-bold") { t("sessions.new.title") }

      div(class: "mb-6 flex flex-col gap-3 sm:flex-row") do
        if Configs::GoogleOauth.configured?
          render Components::OauthButton::Google.new(
            path: user_google_oauth2_omniauth_authorize_path,
            label: t("sessions.new.continue_with_google")
          )
        end

        if Configs::AppleOauth.configured?
          render Components::OauthButton::Apple.new(
            path: user_apple_omniauth_authorize_path,
            label: t("sessions.new.continue_with_apple")
          )
        end

        if Configs::GithubOauth.configured?
          render Components::OauthButton::Github.new(
            path: user_github_omniauth_authorize_path,
            label: t("sessions.new.continue_with_github")
          )
        end
      end

      form_with(url: user_session_path, scope: :user, class: "contents") do |form|
        render RubyUI::FormField.new(class: "my-5") do
          render RubyUI::FormFieldLabel.new(for: :email) { User.human_attribute_name(:email) }
          form.email_field :email,
                           required: true,
                           autofocus: true,
                           autocomplete: "username",
                           placeholder: t("helpers.placeholder.user.email"),
                           value: view_context.params[:email],
                           class: "block shadow-sm rounded-md border border-border-muted px-3 py-2 mt-2 w-full bg-surface-muted text-content placeholder:text-content-muted focus:outline-none focus:ring-2 focus:ring-brand focus:border-transparent transition-colors duration-200"
        end

        render RubyUI::FormField.new(class: "my-5") do
          render RubyUI::FormFieldLabel.new(for: :password) { User.human_attribute_name(:password) }
          form.password_field :password,
                              required: true,
                              autocomplete: "current-password",
                              placeholder: t("helpers.placeholder.user.password"),
                              maxlength: 72,
                              class: "block shadow-sm rounded-md border border-border-muted px-3 py-2 mt-2 w-full bg-surface-muted text-content placeholder:text-content-muted focus:outline-none focus:ring-2 focus:ring-brand focus:border-transparent transition-colors duration-200"
        end

        div(class: "col-span-6 flex flex-col gap-3 sm:flex-row sm:items-center sm:gap-4") do
          render RubyUI::Button.new(
            type: "submit",
            variant: :primary,
            size: :lg,
            class: "w-full sm:w-auto rounded-md bg-brand-solid hover:bg-brand-solid-hover text-brand-foreground font-medium cursor-pointer focus:outline-none focus:ring-2 focus:ring-brand focus:ring-offset-2 focus:ring-offset-app"
          ) { t("sessions.new.submit") }

          render RubyUI::Link.new(
            href: new_user_registration_path,
            variant: :primary,
            size: :lg,
            class: "w-full sm:w-auto text-center rounded-md bg-surface-muted hover:bg-surface-hover text-content font-medium cursor-pointer focus:outline-none focus:ring-2 focus:ring-brand focus:ring-offset-2 focus:ring-offset-app"
          ) { t("sessions.new.sign_up") }

          render RubyUI::Link.new(
            href: new_user_password_path,
            variant: :outline,
            size: :lg,
            class: "w-full sm:w-auto text-center rounded-md border-border-muted bg-transparent shadow-none text-content-secondary hover:bg-surface-hover hover:text-content font-medium cursor-pointer focus:outline-none focus:ring-2 focus:ring-brand focus:ring-offset-2 focus:ring-offset-app"
          ) { t("sessions.new.forgot_password") }

          if confirmation_required?
            render RubyUI::Link.new(
              href: new_user_confirmation_path,
              variant: :outline,
              size: :lg,
              class: "w-full sm:w-auto text-center rounded-md border-border-muted bg-transparent shadow-none text-content-secondary hover:bg-surface-hover hover:text-content font-medium cursor-pointer focus:outline-none focus:ring-2 focus:ring-brand focus:ring-offset-2 focus:ring-offset-app"
            ) { t("sessions.new.resend_confirmation") }
          end
        end
      end
    end
  end

  private

  def confirmation_required?
    view_context.flash[:alert] == t("devise.failure.unconfirmed")
  end
end
