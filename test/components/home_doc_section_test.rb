# frozen_string_literal: true

require "test_helper"

class HomeDocSectionTest < ActiveSupport::TestCase
  test "제목을 h2로 그리고 블록 내용을 같은 section 안에 넣는다" do
    html = Components::Home::DocSection.new(title: "제1조 (목적)").call { "본문" }
    doc = Nokogiri::HTML5.fragment(html)

    assert_equal "제1조 (목적)", doc.at_css("section > h2").text.strip
    assert_includes doc.at_css("section").text, "본문"
  end

  # 23곳이 같은 간격·제목 모양을 쓰게 하는 것이 이 컴포넌트의 목적이라 클래스를 고정한다.
  test "단락 간격과 제목 스타일 클래스를 유지한다" do
    doc = Nokogiri::HTML5.fragment(Components::Home::DocSection.new(title: "제목").call { "본문" })

    assert_equal %w[space-y-4], doc.at_css("section")["class"].split
    assert_empty %w[font-semibold text-accent-text mb-3] - doc.at_css("section > h2")["class"].split
  end
end
