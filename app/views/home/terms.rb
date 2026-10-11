# typed: true
# frozen_string_literal: true

class Views::Home::Terms < Views::Base
  include Phlex::Rails::Helpers::ContentFor
  include Phlex::Rails::Helpers::Tag

  def view_template
    content_for(:title, "서비스 약관 | Ruby-News")
    content_for :head, tag.meta(name: "description", content: "Ruby-News 서비스 이용약관 — 서비스 이용 조건 및 회원의 권리와 의무를 안내합니다.")

    div(class: "max-w-3xl mx-auto space-y-10") do
      header(class: "border-b border-border-strong pb-8") do
        render RubyUI::Heading.new(level: 1, class: "font-bold text-content mb-3") { "서비스 이용약관" }
        p(class: "text-sm text-content-secondary") { "최종 수정일: 2025년 1월 1일" }
      end

      render Components::Home::DocSection.new(title: "제1조 (목적)") do
        p(class: "text-content-secondary leading-relaxed") do
          plain "본 약관은 Ruby-News(이하 '서비스')가 제공하는 서비스의 이용 조건 및 절차, 서비스 이용자와 서비스 간의 권리·의무 및 책임 사항을 규정하는 것을 목적으로 합니다."
        end
      end

      render Components::Home::DocSection.new(title: "제2조 (서비스 내용)") do
        p(class: "text-content-secondary leading-relaxed") do
          plain "서비스는 Ruby·Rails 생태계 관련 기술 기사를 AI 보조 번역하여 한국어로 제공합니다. 서비스는 기사 열람, 회원 가입, 댓글 및 반응 기능을 포함하며 운영 상황에 따라 변경될 수 있습니다."
        end
      end

      render Components::Home::DocSection.new(title: "제3조 (회원가입)") do
        p(class: "text-content-secondary leading-relaxed") do
          plain "이용자는 이메일 주소 또는 Google·Apple 소셜 계정을 통해 회원으로 가입할 수 있습니다. 회원 가입 시 서비스는 본 약관 및 개인정보처리방침에 동의한 것으로 간주합니다."
        end
      end

      render Components::Home::DocSection.new(title: "제4조 (이용자의 의무)") do
        ul(class: "text-content-secondary space-y-2 list-disc list-inside") do
          li { "타인의 권리를 침해하거나 명예를 훼손하는 행위를 하지 않습니다." }
          li { "서비스의 정상적 운영을 방해하는 행위(스팸, 악성코드 배포 등)를 하지 않습니다." }
          li { "법령 및 공공질서에 반하는 콘텐츠를 게시하지 않습니다." }
          li { "타인의 계정을 무단으로 사용하거나 사칭하지 않습니다." }
        end
      end

      render Components::Home::DocSection.new(title: "제5조 (콘텐츠 저작권)") do
        p(class: "text-content-secondary leading-relaxed") do
          plain "서비스가 번역·요약한 콘텐츠의 저작권은 원문 저자 및 출처에 귀속됩니다. 서비스는 원문 출처 URL을 명시하며, 콘텐츠를 상업적으로 재배포하거나 무단으로 크롤링하는 것을 금지합니다."
        end
        p(class: "text-content-secondary leading-relaxed") do
          plain "이용자가 서비스 내에 게시한 댓글 등의 콘텐츠에 대한 저작권은 해당 이용자에게 귀속됩니다."
        end
      end

      render Components::Home::DocSection.new(title: "제6조 (서비스 변경 및 중단)") do
        p(class: "text-content-secondary leading-relaxed") do
          plain "서비스는 운영 상 필요에 따라 서비스 내용을 변경하거나 일시적으로 중단할 수 있습니다. 중요한 변경 사항은 서비스 내 공지를 통해 사전에 안내합니다."
        end
      end

      render Components::Home::DocSection.new(title: "제7조 (면책)") do
        p(class: "text-content-secondary leading-relaxed") do
          plain "서비스는 AI 번역의 정확성을 보장하지 않습니다. 기술적 판단에 있어 원문을 반드시 확인하시기 바랍니다. 서비스는 이용자 간 또는 이용자와 제3자 간 분쟁에 관여하지 않으며, 이로 인한 손해에 대해 책임을 지지 않습니다."
        end
      end

      render Components::Home::DocSection.new(title: "제8조 (계정 삭제)") do
        p(class: "text-content-secondary leading-relaxed") do
          plain "이용자는 언제든지 계정 삭제를 요청할 수 있으며, 서비스는 관련 법령이 허용하는 범위 내에서 지체 없이 처리합니다."
        end
      end

      render Components::Home::DocSection.new(title: "제9조 (약관 변경)") do
        p(class: "text-content-secondary leading-relaxed") do
          plain "서비스는 필요한 경우 본 약관을 변경할 수 있으며, 변경 시 서비스 내 공지를 통해 사전에 안내합니다. 변경된 약관은 공지 후 7일이 경과한 날부터 효력이 발생합니다."
        end
      end

      render Components::Home::DocSection.new(title: "제10조 (문의)") do
        ul(class: "text-content-secondary space-y-2") do
          li do
            plain "Mastodon: "
            render RubyUI::Link.new(href: "https://ruby.social/@news_kr", rel: "me", target: "_blank", class: "text-link hover:text-link-hover hover:underline") { "@news_kr@ruby.social" }
          end
        end
      end
    end
  end
end
