# frozen_string_literal: true

require "test_helper"

class Madmin::ResourcesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:admin)
  end

  test "관리 대상 목록과 페이지 정보를 표시한다" do
    %i[articles sites users preferences tags roles].each do |name|
      get public_send("madmin_#{name}_path")

      assert_response :success
      assert_select ".pagination-info"
    end
  end

  test "사이트 페이지 전환은 검색 조건을 유지한다" do
    time = Time.current
    Site.insert_all!(25.times.map do |index|
      { name: "MadminPagination#{index}", client: 0, created_at: time, updated_at: time }
    end)

    get madmin_sites_path(q: "MadminPagination", sort: "id", direction: "asc")

    assert_response :success
    assert_select "tbody tr", count: 20
    assert_select ".pagination .pages a[href*='page=2'][href*='q=MadminPagination'][href*='sort=id']"

    get madmin_sites_path(q: "MadminPagination", sort: "id", direction: "asc", page: 2)

    assert_response :success
    assert_select "tbody tr", count: 5
    assert_select ".pagination .pages [aria-current=page]", text: "2"
  end
end
