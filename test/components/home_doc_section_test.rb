# frozen_string_literal: true

require "test_helper"

class HomeDocSectionTest < ActiveSupport::TestCase
  test "제목을 h2로 그리고 블록 내용을 같은 section 안에 넣는다" do
    html = Components::Home::DocSection.new(title: "제1조 (목적)").call { "본문" }
    doc = Nokogiri::HTML5.fragment(html)

    assert_equal "제1조 (목적)", doc.at_css("section > h2").text.strip
    assert_includes doc.at_css("section").text, "본문"
  end
end
