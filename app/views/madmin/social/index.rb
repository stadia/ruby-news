# typed: true
# frozen_string_literal: true

class Views::Madmin::Social::Index < Views::Base
  include Phlex::Rails::Helpers::ContentFor
  include Phlex::Rails::Helpers::L

  def initialize(social_list:)
    @social_list = social_list
  end

  def view_template
    content_for :title, t("madmin.social.title")
    header(class: "header") { h1 { t("madmin.social.title") } }
    p { t("madmin.social.description") }
    @social_list.each { |social| social_section(social) }
  end

  private

  # madmin은 앱 Tailwind를 불러오지 않으므로 기존 madmin 표·링크 구조를 쓴다.
  def social_section(social)
    value = social.value.is_a?(Hash) ? social.value : {}
    token = value["access_token"]
    token = nil unless token.is_a?(String) && token.present?

    section do
      header(class: "header") do
        h2 { social.name }
        div(class: "actions") do
          a(href: social_provider_authorize_path(provider: social.name.split("_").first),
            class: token ? "btn btn-secondary" : "btn btn-primary") do
            token ? t("madmin.social.reauthenticate") : t("madmin.social.connect", name: social.name)
          end
        end
      end
      div(class: "table-scroll") do
        table do
          tbody do
            row(t("madmin.social.status")) { token ? t("madmin.social.connected") : t("madmin.social.disconnected") }
            row(t("madmin.social.permissions")) { t("madmin.social.permissions_description") }
            if token
              row(t("madmin.social.access_token")) { code { "#{token[0..15]}..." } }
              timestamp_row(t("madmin.social.expires_at"), value["expires_at"])
              timestamp_row(t("madmin.social.token_created_at"), value["token_created_at"])
            end
          end
        end
      end
    end
  end

  def row(label, &block)
    tr do
      th(class: "label", scope: "row") { label }
      td(&block)
    end
  end

  def timestamp_row(label, value)
    return unless value.is_a?(Numeric) && value.finite?

    time = Time.zone.at(value)
    return unless time.year.between?(1, 9999)

    formatted = l(time, format: :short)
    row(label) { formatted }
  rescue ArgumentError, RangeError
    nil
  end
end
