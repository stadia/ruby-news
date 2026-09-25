# typed: true
# frozen_string_literal: true

class Components::Layout::Footer < Components::Base
  def view_template
    render_footer
  end

  private

  def render_footer
    footer(class: "bg-surface text-content-secondary rounded-lg shadow-sm m-4 border border-border-strong border-t-2 border-t-brand") do
      div(class: "w-full mx-auto max-w-7xl p-4 flex flex-col items-center gap-3") do
        ul(class: "flex flex-wrap justify-center items-center text-sm font-medium text-content-secondary gap-x-4 gap-y-2") do
          li { render_mastodon_link }
          li { render_twitter_link }
          li { render_github_link }
          li { render_slack_link }
          li { render_discord_link }
          li { render_rss_footer_link }
        end

        span(class: "text-sm text-content-secondary text-center") do
          plain "© 2025 "
          a(
            href: "/",
            class: "hover:underline hover:text-content transition-colors duration-200"
          ) { t("layout.site_name") }
          plain ". All Rights Reserved."
        end

        ul(class: "flex flex-wrap justify-center items-center text-sm font-medium text-content-secondary gap-x-4 gap-y-2") do
          li { render_privacy_policy_link }
          li { render_terms_link }
        end

        div(class: "flex items-center gap-2 text-sm text-content-secondary") do
          span { t("layout.theme") }
          render_theme_toggle
        end
      end
    end
  end

  def render_theme_toggle
    ThemeToggle do |toggle|
      SetLightMode do
        Button(variant: :ghost, icon: true, aria_label: t("layout.theme_light")) do
          svg(
            xmlns: "http://www.w3.org/2000/svg",
            viewbox: "0 0 24 24",
            fill: "currentColor",
            aria_hidden: "true",
            class: "w-4 h-4"
          ) do |s|
            s.path(
              d:
                "M12 2.25a.75.75 0 01.75.75v2.25a.75.75 0 01-1.5 0V3a.75.75 0 01.75-.75zM7.5 12a4.5 4.5 0 119 0 4.5 4.5 0 01-9 0zM18.894 6.166a.75.75 0 00-1.06-1.06l-1.591 1.59a.75.75 0 101.06 1.061l1.591-1.59zM21.75 12a.75.75 0 01-.75.75h-2.25a.75.75 0 010-1.5H21a.75.75 0 01.75.75zM17.834 18.894a.75.75 0 001.06-1.06l-1.59-1.591a.75.75 0 10-1.061 1.06l1.59 1.591zM12 18a.75.75 0 01.75.75V21a.75.75 0 01-1.5 0v-2.25A.75.75 0 0112 18zM7.758 17.303a.75.75 0 00-1.061-1.06l-1.591 1.59a.75.75 0 001.06 1.061l1.591-1.59zM6 12a.75.75 0 01-.75.75H3a.75.75 0 010-1.5h2.25A.75.75 0 016 12zM6.697 7.757a.75.75 0 001.06-1.06l-1.59-1.591a.75.75 0 00-1.061 1.06l1.59 1.591z"
            )
          end
        end
      end
      SetDarkMode do
        Button(variant: :ghost, icon: true, aria_label: t("layout.theme_dark")) do
          svg(
            xmlns: "http://www.w3.org/2000/svg",
            viewbox: "0 0 24 24",
            fill: "currentColor",
            aria_hidden: "true",
            class: "w-4 h-4"
          ) do |s|
            s.path(
              fill_rule: "evenodd",
              d:
                "M9.528 1.718a.75.75 0 01.162.819A8.97 8.97 0 009 6a9 9 0 009 9 8.97 8.97 0 003.463-.69.75.75 0 01.981.98 10.503 10.503 0 01-9.694 6.46c-5.799 0-10.5-4.701-10.5-10.5 0-4.368 2.667-8.112 6.46-9.694a.75.75 0 01.818.162z",
              clip_rule: "evenodd"
            )
          end
        end
      end
    end
  end

  def render_mastodon_link
    a(
      rel: "me",
      href: "https://ruby.social/@news_kr",
      target: "_blank",
      class: "hover:underline hover:text-content flex items-center gap-1"
    ) do
      svg(class: "w-5 h-5", fill: "currentColor", viewBox: "0 0 24 24", xmlns: "http://www.w3.org/2000/svg") do |s|
        s.path(
          d: "M23.268 5.313c-.35-2.578-2.617-4.61-5.304-5.004C17.51.242 15.792 0 11.813 0h-.03c-3.98 0-4.835.242-5.288.309C3.882.692 1.496 2.518.917 5.127.64 6.412.61 7.837.661 9.143c.074 1.874.088 3.745.26 5.611.118 1.24.325 2.47.62 3.68.55 2.237 2.777 4.098 4.96 4.857 2.336.792 4.849.923 7.256.38.265-.061.527-.132.786-.213.585-.184 1.27-.39 1.774-.753a.057.057 0 0 0 .023-.043v-1.809a.052.052 0 0 0-.02-.041.053.053 0 0 0-.046-.01 20.282 20.282 0 0 1-4.709.545c-2.73 0-3.463-1.284-3.674-1.818a5.593 5.593 0 0 1-.319-1.433.056.056 0 0 1 .017-.043.051.051 0 0 1 .043-.017c1.513.359 3.072.538 4.657.546 1.828 0 2.298-.081 3.09-.143 1.897-.149 3.566-.867 3.772-1.531.334-1.076.61-3.495.61-3.495 0-.732-.005-1.603-.05-2.447-.041-.832-.126-1.62-.333-2.377z"
        )
      end
      plain " #{t('layout.footer.mastodon')}"
    end
  end

  def render_twitter_link
    a(
      href: "https://x.com/rubynewskr",
      target: "_blank",
      rel: "noopener noreferrer",
      class: "hover:underline hover:text-content flex items-center gap-1"
    ) do
      svg(class: "w-5 h-5", fill: "currentColor", viewBox: "0 0 24 24", xmlns: "http://www.w3.org/2000/svg") do |s|
        s.path(
          d: "M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z"
        )
      end
      plain " #{t('layout.footer.twitter')}"
    end
  end

  def render_rss_footer_link
    a(
      href: rss_path,
      target: "_blank",
      rel: "noopener noreferrer",
      class: "hover:underline hover:text-content flex items-center gap-1"
    ) do
      render PhlexIcons::Hero::Rss.new(variant: :outline, class: "w-5 h-5")
      plain " #{t('layout.footer.rss')}"
    end
  end

  def render_github_link
    a(
      href: "https://github.com/stadia/ruby-news",
      target: "_blank",
      rel: "noopener noreferrer",
      class: "hover:underline hover:text-content flex items-center gap-1"
    ) do
      svg(xmlns: "http://www.w3.org/2000/svg", viewbox: "0 0 16 16", width: "20", height: "20", aria_hidden: "true", fill: "currentColor") do |s|
        s.path(d: "M6.766 11.328c-2.063-.25-3.516-1.734-3.516-3.656 0-.781.281-1.625.75-2.188-.203-.515-.172-1.609.063-2.062.625-.078 1.468.25 1.968.703.594-.187 1.219-.281 1.985-.281.765 0 1.39.094 1.953.265.484-.437 1.344-.765 1.969-.687.218.422.25 1.515.046 2.047.5.593.766 1.39.766 2.203 0 1.922-1.453 3.375-3.547 3.64.531.344.89 1.094.89 1.954v1.625c0 .468.391.734.86.547C13.781 14.359 16 11.53 16 8.03 16 3.61 12.406 0 7.984 0 3.563 0 0 3.61 0 8.031a7.88 7.88 0 0 0 5.172 7.422c.422.156.828-.125.828-.547v-1.25c-.219.094-.5.156-.75.156-1.031 0-1.64-.562-2.078-1.609-.172-.422-.36-.672-.719-.719-.187-.015-.25-.093-.25-.187 0-.188.313-.328.625-.328.453 0 .844.281 1.25.86.313.452.64.655 1.031.655s.641-.14 1-.5c.266-.265.47-.5.657-.656")
      end
      plain " #{t('layout.footer.github')}"
    end
  end

  def render_slack_link
    a(
      href: oauth_install_path(provider: "slack"),
      target: "_blank",
      rel: "noopener noreferrer",
      class: "hover:underline hover:text-content flex items-center gap-1"
    ) do
      svg(class: "w-5 h-5", fill: "currentColor", viewBox: "0 0 24 24", xmlns: "http://www.w3.org/2000/svg") do |s|
        s.path(
          d: "M5.042 15.165a2.528 2.528 0 0 1-2.52 2.523A2.528 2.528 0 0 1 0 15.165a2.527 2.527 0 0 1 2.522-2.52h2.52v2.52zm1.271 0a2.527 2.527 0 0 1 2.521-2.52 2.527 2.527 0 0 1 2.521 2.52v6.313A2.528 2.528 0 0 1 8.834 24a2.528 2.528 0 0 1-2.521-2.522v-6.313zM8.834 5.042a2.528 2.528 0 0 1-2.521-2.52A2.528 2.528 0 0 1 8.834 0a2.528 2.528 0 0 1 2.521 2.522v2.52H8.834zm0 1.271a2.528 2.528 0 0 1 2.521 2.521 2.528 2.528 0 0 1-2.521 2.521H2.522A2.528 2.528 0 0 1 0 8.834a2.528 2.528 0 0 1 2.522-2.521h6.312zM18.956 8.834a2.528 2.528 0 0 1 2.522-2.521A2.528 2.528 0 0 1 24 8.834a2.528 2.528 0 0 1-2.522 2.521h-2.522V8.834zm-1.27 0a2.528 2.528 0 0 1-2.523 2.521 2.527 2.527 0 0 1-2.52-2.521V2.522A2.527 2.527 0 0 1 15.163 0a2.528 2.528 0 0 1 2.523 2.522v6.312zM15.163 18.956a2.528 2.528 0 0 1 2.523 2.522A2.528 2.528 0 0 1 15.163 24a2.527 2.527 0 0 1-2.52-2.522v-2.522h2.52zm0-1.27a2.527 2.527 0 0 1-2.52-2.523 2.527 2.527 0 0 1 2.52-2.52h6.315A2.528 2.528 0 0 1 24 15.163a2.528 2.528 0 0 1-2.522 2.523h-6.315z"
        )
      end
      plain " #{t('layout.footer.slack')}"
    end
  end

  def render_privacy_policy_link
    a(
      href: privacy_policy_path,
      class: "hover:underline hover:text-content"
    ) { t("layout.footer.privacy_policy") }
  end

  def render_terms_link
    a(
      href: terms_path,
      class: "hover:underline hover:text-content"
    ) { t("layout.footer.terms") }
  end

  def render_discord_link
    a(
      href: oauth_install_path(provider: "discord"),
      target: "_blank",
      rel: "noopener noreferrer",
      class: "hover:underline hover:text-content flex items-center gap-1"
    ) do
      svg(class: "w-5 h-5", fill: "currentColor", viewBox: "0 0 24 24", xmlns: "http://www.w3.org/2000/svg") do |s|
        s.path(
          d: "M20.317 4.369a19.791 19.791 0 0 0-4.885-1.515.074.074 0 0 0-.079.037c-.21.375-.444.864-.608 1.249a18.27 18.27 0 0 0-5.487 0 12.64 12.64 0 0 0-.617-1.249.077.077 0 0 0-.079-.037A19.736 19.736 0 0 0 3.677 4.369a.07.07 0 0 0-.032.027C.533 9.046-.32 13.58.099 18.057a.082.082 0 0 0 .031.056 19.9 19.9 0 0 0 5.993 3.03.078.078 0 0 0 .084-.028c.462-.63.874-1.295 1.226-1.994a.076.076 0 0 0-.041-.106 13.107 13.107 0 0 1-1.872-.892.077.077 0 0 1-.008-.128c.126-.094.252-.192.372-.291a.074.074 0 0 1 .077-.01c3.928 1.793 8.18 1.793 12.061 0a.074.074 0 0 1 .078.009c.12.099.246.198.373.292a.077.077 0 0 1-.006.127 12.299 12.299 0 0 1-1.873.891.077.077 0 0 0-.041.107c.36.698.772 1.362 1.225 1.993a.076.076 0 0 0 .084.028 19.84 19.84 0 0 0 6.002-3.03.077.077 0 0 0 .032-.054c.5-5.177-.838-9.674-3.549-13.66a.061.061 0 0 0-.031-.03zM8.02 15.331c-1.183 0-2.157-1.085-2.157-2.419 0-1.333.956-2.419 2.157-2.419 1.21 0 2.176 1.096 2.157 2.42 0 1.333-.956 2.418-2.157 2.418zm7.974 0c-1.183 0-2.157-1.085-2.157-2.419 0-1.333.955-2.419 2.157-2.419 1.21 0 2.176 1.096 2.157 2.42 0 1.333-.946 2.418-2.157 2.418z"
        )
      end
      plain " #{t('layout.footer.discord')}"
    end
  end
end
