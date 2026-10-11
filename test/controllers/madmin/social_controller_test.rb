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
    assert_select "a.btn.btn-secondary[href=?]", social_provider_authorize_path(provider: "twitter"), text: "재인증"
    assert_select "a.btn.btn-primary[href=?]", social_provider_authorize_path(provider: "linkedin"), text: "linkedin_oauth 연동하기"
    allowed_classes = %w[header actions table-scroll label btn btn-secondary btn-primary]
    assert_select "main > div [class]" do |elements|
      elements.each do |element|
        assert_empty element["class"].split - allowed_classes
      end
    end
  end

  test "비 Hash OAuth 값과 비문자열 토큰은 미연결 상태로 표시한다" do
    values = [ [ "invalid" ], "invalid", 123, true, nil, { "access_token" => 123 },
               { "access_token" => [ "secret" ] }, { "access_token" => { "secret" => true } },
               { "access_token" => true }, { "access_token" => "" } ]
    values.each_with_index do |value, index|
      Preference.create!(name: "invalid#{index}_oauth", value:)
    end
    sign_in_as users(:admin)

    get madmin_social_index_path

    assert_response :success
    assert_select "td", text: "연결 안됨", count: values.size
    assert_select "a.btn.btn-primary", count: values.size
    assert_select "td code", count: 0
    assert_not_includes response.body, "secret"
  end

  test "잘못된 OAuth 타임스탬프가 정상 연결 항목의 표시를 막지 않는다" do
    [ "invalid", "1700000000", [], {}, true, 1e100 ].each_with_index do |timestamp, index|
      Preference.create!(name: "invalid#{index}_oauth", value: {
        "access_token" => "abcdefghijklmnopqrstuvwxyz", "expires_at" => timestamp, "token_created_at" => timestamp
      })
    end
    expires_at = 1_700_000_000
    created_at = 1_699_000_000
    Preference.create!(name: "valid_oauth", value: {
      "access_token" => "abcdefghijklmnopqrstuvwxyz", "expires_at" => expires_at, "token_created_at" => created_at
    })
    sign_in_as users(:admin)

    get madmin_social_index_path

    assert_response :success
    assert_select "td", text: "연결됨", count: 7
    assert_select "a.btn.btn-secondary", count: 7
    assert_select "td code", text: "abcdefghijklmnop...", count: 7
    assert_select "th", text: "만료 시간", count: 1
    assert_select "th", text: "생성 시간", count: 1
    assert_select "td", text: I18n.l(Time.zone.at(expires_at), format: :short)
    assert_select "td", text: I18n.l(Time.zone.at(created_at), format: :short)
    assert_not_includes response.body, "abcdefghijklmnopqrstuvwxyz"
  end
end
