# typed: true
# frozen_string_literal: true

class Components::Layout::NavBar < Components::Base
  include Phlex::Rails::Helpers::LinkTo
  include Phlex::Rails::Helpers::FormWith

  def view_template
    render_navigation
  end

  private

  def render_navigation
    nav(
      class: "bg-surface border-b border-border-strong border-t-4 border-t-brand",
      aria_label: t("layout.nav.aria_label")
    ) do
      div(class: "max-w-[1400px] flex flex-wrap md:flex-nowrap items-center justify-between mx-auto p-4") do
        link_to root_path, class: "flex items-center space-x-3 rtl:space-x-reverse group min-w-0 md:min-w-fit" do
          span(class: "self-center text-xl md:text-2xl font-semibold text-content group-hover:text-link-hover transition-colors duration-200 md:whitespace-nowrap") do
            plain "Ruby-News || "
            span(class: "text-accent-text") { t("layout.brand_subtitle") }
          end
        end

        render_mobile_menu_toggle
        render_nav_menu
      end
    end
  end

  def render_mobile_menu_toggle
    input(type: "checkbox", id: "mobile-menu-toggle", class: "mobile-menu-toggle peer")
    label(
      for: "mobile-menu-toggle",
      class: "inline-flex items-center p-2 w-11 h-11 justify-center text-sm text-content rounded-lg md:hidden hover:bg-surface-muted focus:outline-none focus:ring-2 focus:ring-brand focus:ring-offset-2 focus:ring-offset-surface cursor-pointer",
      aria_label: t("layout.nav.menu_toggle")
    ) do
      span(class: "sr-only") { t("layout.nav.open_main_menu") }
      render PhlexIcons::Hero::Bars3.new(variant: :outline, class: "w-5 h-5")
    end
  end

  def render_nav_menu
    vc = view_context
    div(
      class: "items-center justify-between w-full md:flex md:w-auto md:order-1 hidden peer-checked:block transition-all duration-300 ease-in-out md:transition-none",
      id: "navbar-search"
    ) do
      # 일본어는 메뉴 텍스트 폭이 넓어 데스크탑 간격을 좁힌다.
      nav_spacing = (I18n.locale == :ja) ? "md:space-x-4" : "md:space-x-8"
      ul(class: "flex flex-col gap-y-3 md:gap-y-0 p-4 md:p-0 mt-4 font-medium border border-border-strong rounded-lg bg-surface-muted #{nav_spacing} rtl:space-x-reverse md:flex-row md:items-center md:mt-0 md:border-0 md:bg-surface animate-in slide-in-from-top-2 fade-in duration-200 md:animate-none") do
        li { raw vc.nav_link_to(t("layout.nav.home"), root_path) }
        li { raw vc.nav_link_to(t("layout.nav.past_articles"), articles_path) }
        li { raw vc.nav_link_to(t("layout.nav.other_news"), others_path) }
        li { raw vc.nav_link_to(t("layout.nav.feed"), feed_path) } if vc.user_signed_in?
        li { raw vc.nav_link_to(t("layout.nav.new_article"), new_article_path) } if vc.user_signed_in?
        li(class: "flex items-center px-4 md:px-0") { render_search_form }

        if vc.user_signed_in?
          li(class: "flex items-center px-4 md:px-0") { render_user_menu(vc) }
        else
          li { raw vc.nav_link_to(t("sign_in"), new_user_session_path) }
        end
      end
    end
  end

  def render_user_menu(vc)
    user = vc.current_user
    name = user.username || user.name
    DropdownMenu(options: { placement: "bottom-end" }) do
      DropdownMenuTrigger do
        button(
          type: "button",
          class: "flex items-center rounded-full focus:outline-none focus:ring-2 focus:ring-brand focus:ring-offset-2 focus:ring-offset-surface cursor-pointer",
          aria_label: name
        ) do
          render Components::UserAvatar.new(user: user, name: name)
        end
      end
      DropdownMenuContent do
        DropdownMenuLabel { name }
        DropdownMenuSeparator()
        DropdownMenuItem(href: user_profile_path(user)) do
          render PhlexIcons::Hero::User.new(variant: :outline, class: "w-4 h-4 mr-2 shrink-0 text-content-secondary")
          plain t("layout.nav.profile")
        end
        DropdownMenuItem(href: edit_user_registration_path) do
          render PhlexIcons::Hero::Cog6Tooth.new(variant: :outline, class: "w-4 h-4 mr-2 shrink-0 text-content-secondary")
          plain t("layout.nav.settings")
        end
        DropdownMenuSeparator()
        DropdownMenuItem(href: destroy_user_session_path) do
          render PhlexIcons::Hero::ArrowRightOnRectangle.new(variant: :outline, class: "w-4 h-4 mr-2 shrink-0 text-content-secondary")
          plain t("sign_out")
        end
      end
    end
  end

  def render_search_form
    form_with(
      url: articles_path,
      method: :get,
      local: true,
      html: {
        role: "search",
        aria_label: t("layout.search.aria_label"),
        class: "flex items-center space-x-2"
      }
    ) do |form|
      raw form.text_field(
        :search,
        placeholder: t("helpers.placeholder.search.articles"),
        value: view_context.params[:search],
        class: "px-3 py-2 text-sm text-content bg-app border border-input rounded-lg focus:outline-none focus:ring-2 focus:ring-brand focus:border-transparent w-40 md:w-48 transition-all duration-200 placeholder:text-content-muted"
      )
      render Button.new(
        type: "submit",
        variant: :primary,
        size: :lg,
        class: "font-medium bg-brand-solid rounded-lg border border-brand-solid hover:bg-brand-solid-hover text-brand-foreground focus:ring-2 focus:outline-none focus:ring-brand focus:ring-offset-2 focus:ring-offset-surface transition-all duration-150 min-h-11 cursor-pointer"
      ) { t("layout.search.submit") }
    end
  end
end
