# typed: true
# frozen_string_literal: true

class Views::Home::PrivacyPolicy < Views::Base
  include Phlex::Rails::Helpers::ContentFor
  include Phlex::Rails::Helpers::Tag

  def view_template
    content_for(:title, "개인정보처리방침 | Ruby-News")
    content_for :head, tag.meta(name: "description", content: "Ruby-News 개인정보처리방침 — 수집하는 개인정보의 항목, 이용 목적, 보유 기간 등을 안내합니다.")

    div(class: "max-w-3xl mx-auto space-y-10") do
      header(class: "border-b border-border-strong pb-8") do
        render RubyUI::Heading.new(level: 1, class: "font-bold text-content mb-3") { "개인정보처리방침" }
        p(class: "text-sm text-content-secondary") { "최종 수정일: 2025년 1월 1일" }
      end

      render Components::Home::DocSection.new(title: "1. 총칙") do
        p(class: "text-content-secondary leading-relaxed") do
          plain "Ruby-News(이하 '서비스')는 이용자의 개인정보를 소중히 여기며 「개인정보 보호법」 등 관련 법령을 준수합니다. 본 방침은 서비스가 수집하는 개인정보의 항목, 이용 목적, 보유 기간 및 이용자의 권리를 안내합니다."
        end
      end

      render Components::Home::DocSection.new(title: "2. 수집하는 개인정보 항목") do
        p(class: "text-content-secondary leading-relaxed") { "서비스는 다음과 같은 개인정보를 수집합니다." }
        ul(class: "text-content-secondary space-y-2 list-disc list-inside") do
          li do
            strong(class: "text-content") { "회원가입 시" }
            plain ": 이메일 주소, 사용자명(닉네임)"
          end
          li do
            strong(class: "text-content") { "소셜 로그인(Google·Apple) 시" }
            plain ": 소셜 계정에서 제공하는 이메일 주소, 이름(제공하는 경우)"
          end
          li do
            strong(class: "text-content") { "서비스 이용 과정" }
            plain ": 접속 IP, 쿠키, 서비스 이용 기록"
          end
        end
      end

      render Components::Home::DocSection.new(title: "3. 개인정보 이용 목적") do
        ul(class: "text-content-secondary space-y-1 list-disc list-inside") do
          li { "회원 식별 및 서비스 제공" }
          li { "서비스 이용 현황 파악 및 통계 분석" }
          li { "불법·부정 이용 방지" }
          li { "법령 상 의무 이행" }
        end
      end

      render Components::Home::DocSection.new(title: "4. 개인정보 보유 및 이용 기간") do
        p(class: "text-content-secondary leading-relaxed") do
          plain "이용자가 회원 탈퇴를 요청하거나 개인정보 삭제를 요구하는 경우 지체 없이 파기합니다. 단, 관계 법령에 따라 보존이 필요한 경우 해당 기간 동안 안전하게 보관합니다."
        end
      end

      render Components::Home::DocSection.new(title: "5. 제3자 제공") do
        p(class: "text-content-secondary leading-relaxed") do
          plain "서비스는 이용자의 개인정보를 원칙적으로 제3자에게 제공하지 않습니다. 다만, 이용자의 동의가 있거나 법령에 의한 경우에는 예외로 합니다."
        end
      end

      render Components::Home::DocSection.new(title: "6. 소셜 로그인(OAuth)") do
        p(class: "text-content-secondary leading-relaxed") do
          plain "Google 또는 Apple 계정으로 로그인하는 경우, 해당 서비스의 개인정보처리방침이 함께 적용됩니다. 서비스는 소셜 계정 연동 시 제공받은 정보만을 사용하며, 소셜 서비스 내 활동에는 관여하지 않습니다."
        end
      end

      render Components::Home::DocSection.new(title: "7. 이용자의 권리") do
        p(class: "text-content-secondary leading-relaxed") { "이용자는 언제든지 다음 권리를 행사할 수 있습니다." }
        ul(class: "text-content-secondary space-y-1 list-disc list-inside") do
          li { "개인정보 열람 요청" }
          li { "개인정보 정정·삭제 요청" }
          li { "개인정보 처리 정지 요청" }
          li { "회원 탈퇴(계정 삭제)" }
        end
        p(class: "text-content-secondary leading-relaxed mt-3") do
          plain "권리 행사는 아래 연락처로 문의해 주세요."
        end
      end

      render Components::Home::DocSection.new(title: "8. 개인정보 보호책임자") do
        ul(class: "text-content-secondary space-y-2") do
          li do
            plain "Mastodon: "
            render RubyUI::Link.new(href: "https://ruby.social/@news_kr", rel: "me", target: "_blank", class: "text-link hover:text-link-hover hover:underline") { "@news_kr@ruby.social" }
          end
        end
      end

      render Components::Home::DocSection.new(title: "9. 방침 변경") do
        p(class: "text-content-secondary leading-relaxed") do
          plain "본 방침은 법령 또는 서비스 변경에 따라 수정될 수 있으며, 변경 시 서비스 내 공지를 통해 안내합니다."
        end
      end
    end
  end
end
