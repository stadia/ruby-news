# typed: true
# frozen_string_literal: true

class Views::Home::About < Views::Base
  include Phlex::Rails::Helpers::ContentFor
  include Phlex::Rails::Helpers::Tag

  def view_template
    content_for(:title, "소개 | Ruby-News")
    content_for :head, tag.meta(name: "description", content: "Ruby-News는 Ruby·Rails 생태계 소식을 AI 보조 번역으로 매일 한국어로 제공하는 기술 뉴스 집약 서비스입니다.")

    div(class: "max-w-3xl mx-auto space-y-10") do
      header(class: "border-b border-border-strong pb-8") do
        render RubyUI::Heading.new(level: 1, class: "font-bold text-content mb-3") { "Ruby-News 소개" }
        p(class: "text-lg text-content-secondary") do
          plain "Ruby·Rails 생태계 소식을 AI 보조 번역으로 매일 한국어로 제공하는 기술 뉴스 집약 서비스입니다."
        end
      end

      render Components::Home::DocSection.new(title: "서비스 소개") do
        p(class: "text-content-secondary leading-relaxed") do
          plain "Ruby-News는 전 세계 Ruby 및 Ruby on Rails 커뮤니티에서 발행되는 기술 아티클, 릴리즈 노트, 보안 권고, 컨퍼런스 자료를 매일 수집하여 한국어로 번역·요약합니다. 한국어권 Ruby 개발자가 언어 장벽 없이 최신 생태계 동향을 파악할 수 있도록 만들어졌습니다."
        end
        ul(class: "text-content-secondary space-y-1 list-disc list-inside") do
          li { "누적 기사 2,400개 이상 — 매일 업데이트" }
          li { "Ruby 버전 릴리즈, Rails 업그레이드 가이드, CVE 보안 권고" }
          li { "RubyGems 신규 릴리즈, 성능 최적화, Hotwire·Turbo 패턴" }
          li { "RubyKaigi, Rails World 등 커뮤니티 행사 소식" }
        end
      end

      render Components::Home::DocSection.new(title: "콘텐츠 제작 방식") do
        p(class: "text-content-secondary leading-relaxed") do
          plain "모든 기사는 "
          strong(class: "text-content") { "AI 보조 번역" }
          plain "을 통해 제작됩니다. 원문 영어 아티클을 AI가 한국어로 번역하고 핵심 내용을 3개 요점으로 요약합니다. 각 기사 페이지에는 원문 출처 URL이 명시되어 있으며, 독자가 원문을 직접 확인할 수 있습니다."
        end
        p(class: "text-content-secondary leading-relaxed") do
          plain "번역의 정확성을 위해 노력하지만, AI 번역의 특성상 오역이 있을 수 있습니다. 중요한 기술적 판단에는 반드시 원문을 함께 참고하시기 바랍니다."
        end
      end

      render Components::Home::DocSection.new(title: "큐레이션 기준") do
        p(class: "text-content-secondary leading-relaxed") do
          plain "Ruby·Rails 생태계에 직접적으로 관련된 콘텐츠를 중심으로 수집합니다. ruby-lang.org, rubyonrails.org, RubyGems, thoughtbot, Evil Martians, HackerNews, YouTube 기술 채널 등 신뢰할 수 있는 출처를 우선합니다."
        end
      end

      render Components::Home::DocSection.new(title: "연락처") do
        ul(class: "text-content-secondary space-y-2") do
          li do
            plain "Mastodon: "
            render RubyUI::Link.new(href: "https://ruby.social/@news_kr", rel: "me", target: "_blank", class: "text-link hover:text-link-hover hover:underline") { "@news_kr@ruby.social" }
          end
          li do
            plain "Twitter/X: "
            render RubyUI::Link.new(href: "https://x.com/rubynewskr", target: "_blank", rel: "noopener noreferrer", class: "text-link hover:text-link-hover hover:underline") { "@rubynewskr" }
          end
        end
      end
    end
  end
end
