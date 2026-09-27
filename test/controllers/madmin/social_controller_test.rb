# frozen_string_literal: true

require "test_helper"

class Madmin::SocialControllerTest < ActionDispatch::IntegrationTest
  # madmin 레이아웃은 앱 Tailwind(app.css)를 불러오지 않으므로 Tailwind 팔레트 클래스는
  # 적용되지 않는다. madmin CSS의 header/table/btn 구조만 쓴다.
  test "소셜 연동 목록을 madmin 표 구조로 그린다" do
    Preference.create!(name: "twitter_oauth", value: { "access_token" => "abcdefghijklmnopqrstuvwxyz" })
    Preference.create!(name: "linkedin_oauth", value: {})
    sign_in_as users(:admin)

    get madmin_social_index_path

    assert_response :success
    assert_select "header.header h1", text: "소셜 미디어 연동"
    assert_select ".table-scroll table", 2
    assert_select "td", text: "연결됨"
    assert_select "td", text: "연결 안됨"
    assert_select "td code", text: "abcdefghijklmnop..."
    assert_select "a.btn.btn-secondary", text: "재인증"
    assert_select "a.btn.btn-primary", text: "linkedin_oauth 연동하기"
    assert_select "[class*='gray-'], [class*='bg-white'], [class*='text-white'], [class*='blue-'], [class*='green-']", 0
  end
end
