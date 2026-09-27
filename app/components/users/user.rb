# typed: true
# frozen_string_literal: true

class Components::Users::User < Components::Base
  include Phlex::Rails::Helpers::DOMID

  def initialize(user:)
    @user = user
  end

  def view_template
    render RubyUI::Card.new(id: dom_id(@user), class: "w-full max-w-2xl bg-app/40 border-border-subtle rounded-2xl overflow-hidden shadow-2xl my-6") do
      # Profile Header/Banner
      div(class: "h-24 bg-linear-to-r from-surface to-surface-muted/50 border-b border-border-subtle")

      render RubyUI::CardContent.new(class: "px-6 pb-8 sm:px-10 sm:pb-10 pt-0") do
        # Avatar & Primary Identity
        div(class: "flex flex-col sm:flex-row items-center sm:items-end gap-6 -mt-12 mb-10") do
          render RubyUI::Avatar.new(size: :xl, class: "h-24 w-24 ring-4 ring-app bg-app shadow-xl") do
            if @user.avatar_attached?
              render RubyUI::AvatarImage.new(src: @user.avatar_url, alt: @user.name)
            else
              render RubyUI::AvatarFallback.new(class: "bg-brand-solid text-brand-foreground text-3xl font-bold") do
                initials
              end
            end
          end

          div(class: "text-center sm:text-left pb-1 flex-1") do
            h2(class: "text-3xl font-bold text-content tracking-tight") { @user.name }
            p(class: "text-content-muted font-medium text-lg mt-1") { @user.email }
          end
        end

        # Details Grid
        div(class: "grid grid-cols-1 md:grid-cols-2 gap-x-12 gap-y-8 pt-8 border-t border-border-subtle/60") do
          detail_field(::User.human_attribute_name(:email), @user.email)
          detail_field(::User.human_attribute_name(:name), @user.name)
        end
      end
    end
  end

  def badge(text)
    render RubyUI::Badge.new(variant: :slate, size: :sm) { text }
  end

  private

  def detail_field(label, value = nil, &block)
    div(class: "space-y-2") do
      span(class: "text-[10px] font-bold uppercase tracking-[0.2em] text-content-muted") { label }
      if block
        yield
      else
        p(class: "text-content-secondary font-medium text-lg") { value }
      end
    end
  end

  def initials
    (@user.name.presence || @user.email).first.upcase
  end
end
