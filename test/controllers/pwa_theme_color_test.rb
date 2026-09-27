# frozen_string_literal: true

require "test_helper"

# 브라우저 UI(주소창, PWA 창 테두리) 색은 페이지 배경(bg-app)과 같아야 한다.
# 라이트 neutral-50, 다크 neutral-900.
class PwaThemeColorTest < ActionDispatch::IntegrationTest
  LIGHT = "#f8fafc"
  DARK = "#0f172a"

  test "head에 OS 테마별 theme-color 메타를 둔다" do
    get root_path

    assert_response :success
    assert_select "meta[name='theme-color'][data-theme='light'][media='(prefers-color-scheme: light)'][content='#{LIGHT}']", 1
    assert_select "meta[name='theme-color'][data-theme='dark'][media='(prefers-color-scheme: dark)'][content='#{DARK}']", 1
  end

  test "manifest는 테마별 값을 지원하지 않으므로 theme_color와 background_color에 다크 배경색을 쓴다" do
    get pwa_manifest_path(format: :json)

    assert_response :success
    manifest = JSON.parse(response.body)

    assert_equal DARK, manifest["theme_color"]
    assert_equal DARK, manifest["background_color"]
  end
end
