# frozen_string_literal: true

require "test_helper"

class LayoutFooterTest < ActionDispatch::IntegrationTest
  # 콜백은 install이 세션에 저장한 state만 받으므로, 공급자 authorize URL로 바로 보내면 연동이 항상 거부된다.
  test "Slack·Discord 연결 링크는 state를 발급하는 install 경로를 거친다" do
    get root_path

    assert_select "footer a[href=?]", oauth_install_path(provider: "slack")
    assert_select "footer a[href=?]", oauth_install_path(provider: "discord")
    assert_select "footer a[href*='slack.com/oauth']", count: 0
    assert_select "footer a[href*='discord.com/oauth2']", count: 0
  end

  # 버튼 이름은 누르면 일어나는 일이어야 한다. 라이트 모드에서 보이는 버튼은 다크로 바꾼다.
  test "테마 전환 버튼의 접근 가능한 이름은 누르면 바뀔 테마를 말한다" do
    get root_path

    assert_select "footer [data-action$='#setDarkTheme'] button[aria-label=?]", "다크 모드로 전환"
    assert_select "footer [data-action$='#setLightTheme'] button[aria-label=?]", "라이트 모드로 전환"
  end
end
