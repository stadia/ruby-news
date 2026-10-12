# typed: true
# frozen_string_literal: true

class Components::Layout < Components::Base
  include Phlex::Rails::Layout

  def view_template
    doctype
    html(lang: I18n.locale, class: "light theme-light") do
      head do
        render Components::Layout::AssetPreloads.new(section: :preconnect)
        render Components::Layout::AssetPreloads.new(section: :theme_color)
        render_theme_init_script
        render_analytics_scripts
        render Components::Layout::MetaTags.new
        csrf_meta_tags
        csp_meta_tag
        yield(:head)
        render Components::Layout::AssetPreloads.new(section: :pwa_and_icons)
        render Components::Layout::AssetPreloads.new(section: :google_fonts)
        # tailwind만 링크한다. `:app`은 app/assets/**/*.css를 펼쳐 vendor/lightgallery.css까지
        # 렌더 차단으로 만들었다(#1108). lightgallery.css는 lightbox 컨트롤러가 연결될 때만 주입한다.
        stylesheet_link_tag "tailwind", data_turbo_track: "reload"
        # lexxy.css는 @import 체인(lexxy → content/editor → variables)이라 직접 링크보다
        # 직렬 왕복이 2번 더 생긴다(#1108).
        stylesheet_link_tag "lexxy-variables", "lexxy-content", "lexxy-editor", data_turbo_track: "reload"
        javascript_importmap_tags
        render_controller_entry_preloads
        render Components::Layout::StructuredData.new
      end

      body(
        class: "bg-app text-content-secondary min-h-screen flex flex-col",
        data: {
          controller: "page-loader",
          action: [
            "turbo:before-visit@window->page-loader#beforeTurboVisit",
            "turbo:load@window->page-loader#afterTurboLoad"
          ].join(" ")
        }
      ) do
        render_skip_link
        render_loading_indicator
        render Components::Layout::NavBar.new unless view_context.hotwire_native_app?
        render_main { yield }
        render Components::Layout::Footer.new unless view_context.hotwire_native_app?
      end
    end
  end

  # application.js → controllers(index.js) → application·page_loader_controller로 이어지는 정적
  # import 체인의 importmap 이름. pin_all_from preload: false라 그대로 두면 HTML 이후 직렬 왕복이
  # 2번 더 생긴다(#1108). controllers/index.js의 import 목록과 맞춰 둔다(테스트가 대조한다).
  CONTROLLER_ENTRY_MODULES = %w[controllers controllers/application controllers/page_loader_controller].freeze

  private

  # importmap JSON은 요청 host와 무관하게 프로세스 단위로 캐시된다. asset_host 람다가 host마다
  # 다른 URL을 주므로, asset_path로 따로 풀면 preload URL이 importmap과 어긋나 재사용되지 않는다.
  def render_controller_entry_preloads
    vc = view_context
    imports = JSON.parse(Rails.application.importmap.to_json(resolver: vc)).fetch("imports")
    raw(vc.javascript_module_preload_tag(*imports.values_at(*CONTROLLER_ENTRY_MODULES)))
  end

  def render_theme_init_script
    script do
      raw(<<~JS.html_safe)
        (function(){
          var d=document.documentElement;
          var storedTheme;
          try { storedTheme=localStorage.theme; } catch(e) { storedTheme=null; }
          var prefersDark=window.matchMedia('(prefers-color-scheme: dark)').matches;
          var dark=storedTheme==='dark'||(storedTheme!=='light'&&prefersDark);
          d.classList.toggle('dark',dark);
          d.classList.toggle('light',!dark);
          d.classList.toggle('theme-dark',dark);
          d.classList.toggle('theme-light',!dark);
          document.querySelectorAll('meta[name="theme-color"][data-theme]').forEach(function(meta){
            var theme=meta.dataset.theme;
            meta.media=storedTheme==='light'||storedTheme==='dark'
              ? (theme===storedTheme?'all':'not all')
              : '(prefers-color-scheme: '+theme+')';
          });
        })();
      JS
    end
  end

  def render_analytics_scripts
    ga_id = Hosts::GA_ID_FOR_HOST.fetch(view_context.request.host, Hosts::DEFAULT_GA_ID)

    script(async: true, src: "https://www.googletagmanager.com/gtag/js?id=#{ga_id}")
    script do
      raw(<<~JS.html_safe)
        window.dataLayer = window.dataLayer || [];
        function gtag(){dataLayer.push(arguments);}
        gtag('js', new Date());
        gtag('config', '#{ga_id}');
      JS
    end
  end

  def render_skip_link
    a(
      href: "#main-content",
      class: "sr-only focus:not-sr-only focus:absolute focus:top-4 focus:left-4 focus:z-50 focus:px-4 focus:py-2 focus:bg-brand-solid focus:text-brand-foreground focus:rounded-lg focus:shadow-lg"
    ) { t("layout.skip_to_content") }
  end

  def render_loading_indicator
    div(
      data: { page_loader_target: "loader" },
      class: "fixed inset-0 bg-app/75 z-50 hidden items-center justify-center"
    ) do
      div(class: "flex flex-col items-center space-y-4") do
        div(class: "animate-spin rounded-full h-12 w-12 border-4 border-brand border-t-transparent shadow-lg shadow-brand/50")
        div(class: "text-content font-medium") { t("layout.loading") }
      end
    end
  end

  def render_main
    vc = view_context
    main(id: "main-content", class: "container mx-auto px-4 py-8 grow") do
      if vc.user_signed_in? && Configs::WebPush.configured?
        div(
          data: {
            controller: "push-notifications",
            push_notifications_public_key_value: Configs::WebPush.public_key,
            push_notifications_subscription_url_value: push_subscription_path,
            push_notifications_service_worker_path_value: pwa_service_worker_path(format: :js),
            push_notifications_cooldown_hours_value: "1"
          }
        ) do
          render Components::PushNotifications::PromptModal.new
        end
      end

      render Components::Flash.new
      yield
    end
  end
end
