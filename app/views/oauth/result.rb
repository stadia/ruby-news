# typed: true
# frozen_string_literal: true

class Views::Oauth::Result < Views::Base
  include Phlex::Rails::Helpers::ContentFor

  def initialize(provider:, success:, channel_name: nil, error: nil)
    @provider = provider
    @success = success
    @channel_name = channel_name
    @error = error
  end

  def view_template
    provider_name = @provider&.capitalize
    title = @success ? t("oauth.result.success_title", provider: provider_name) : t("oauth.result.failure_title", provider: provider_name)

    content_for(:title, t("oauth.result.page_title", title: title))

    div(class: "max-w-lg mx-auto mt-16 px-4 space-y-6") do
      render RubyUI::Card.new do
        render RubyUI::CardHeader.new do
          div(class: "flex items-center gap-3") do
            if @success
              render PhlexIcons::Hero::CheckCircle.new(variant: :outline, class: "w-8 h-8 text-success")
            else
              render PhlexIcons::Hero::XCircle.new(variant: :outline, class: "w-8 h-8 text-danger-text")
            end
            render RubyUI::Heading.new(level: 2) { title }
          end
        end

        render RubyUI::CardContent.new do
          if @success
            div(class: "space-y-2") do
              p(class: "text-content-secondary") do
                if @channel_name.present?
                  kind = @provider == "slack" ? t("oauth.result.workspace") : t("oauth.result.server")
                  t("oauth.result.channel_connected", channel: @channel_name, kind: kind)
                else
                  t("oauth.result.provider_connected", provider: provider_name)
                end
              end
            end
          else
            div(class: "space-y-2") do
              p(class: "text-content-secondary") { t("oauth.result.failure_message", provider: provider_name) }
              if @error.present?
                p(class: "text-sm text-danger-text bg-destructive/10 rounded px-3 py-2") { @error }
              end
            end
          end
        end
      end

      if @success
        render RubyUI::Card.new do
          render RubyUI::CardHeader.new do
            render RubyUI::Heading.new(level: 3) { t("oauth.result.notification_guide_heading") }
          end

          render RubyUI::CardContent.new do
            div(class: "space-y-3 text-sm text-content-secondary") do
              p { t("oauth.result.webhook_configured", provider: provider_name) }
              p { t("oauth.result.no_bot_required") }
            end
          end
        end
      end

      div(class: "text-center") do
        render RubyUI::Link.new(href: root_path) { t("oauth.result.back_to_home") }
      end
    end
  end
end
