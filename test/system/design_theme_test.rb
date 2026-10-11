# frozen_string_literal: true

require "application_system_test_case"

class DesignThemeTest < ApplicationSystemTestCase
  test "회원 카드의 모서리는 24px를 유지한다" do
    visit new_user_registration_path

    card = find("form .rounded-2xl", match: :first)

    assert_equal "24px", card.evaluate_script("getComputedStyle(this).borderTopLeftRadius")
  end

  test "테마 선택은 주소창 색을 바꾸고 선택을 지우면 OS media로 복원한다" do
    visit root_path
    page.execute_script("localStorage.theme = 'light'")
    page.refresh

    find('footer button[aria-label="다크 모드로 전환"]').click

    assert_equal [ [ "light", "not all" ], [ "dark", "all" ] ], theme_media
    find('footer button[aria-label="라이트 모드로 전환"]').click

    assert_equal [ [ "light", "all" ], [ "dark", "not all" ] ], theme_media

    page.execute_script(<<~JS)
      localStorage.removeItem('theme');
      const element = document.querySelector('[data-controller~="ruby-ui--theme-toggle"]');
      window.Stimulus.getControllerForElementAndIdentifier(element, 'ruby-ui--theme-toggle').setTheme();
    JS

    assert_equal [ [ "light", "(prefers-color-scheme: light)" ], [ "dark", "(prefers-color-scheme: dark)" ] ], theme_media
  end

  test "모듈 로드 없이도 첫 화면의 주소창 색은 저장된 테마를 따른다" do
    visit root_path
    page.execute_script("localStorage.theme = 'light'")
    browser = page.driver.browser
    browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-color-scheme", value: "dark" } ])
    browser.execute_cdp("Network.enable")
    browser.execute_cdp("Network.setBlockedURLs", urls: [ "*.js*", "*googletagmanager*" ])
    page.refresh

    assert_equal "undefined", page.evaluate_script("typeof window.Stimulus")
    assert_selector "html.theme-light"
    assert_equal [ [ "light", "all" ], [ "dark", "not all" ] ], theme_media
  ensure
    browser&.execute_cdp("Network.setBlockedURLs", urls: [])
    browser&.execute_cdp("Emulation.setEmulatedMedia", features: [])
  end

  test "저장소 읽기가 차단돼도 초기 스크립트와 컨트롤러는 OS 테마를 적용한다" do
    visit root_path
    browser = page.driver.browser
    script = browser.execute_cdp("Page.addScriptToEvaluateOnNewDocument", source: <<~JS)
      Object.defineProperty(window, 'localStorage', {
        get() { throw new DOMException('Blocked', 'SecurityError'); }
      });
    JS
    browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-color-scheme", value: "dark" } ])
    browser.execute_cdp("Network.enable")

    [ true, false ].each do |block_modules|
      browser.execute_cdp("Network.setBlockedURLs", urls: block_modules ? [ "*.js*", "*googletagmanager*" ] : [])
      page.refresh
      unless block_modules
        page.execute_script(<<~JS)
          const element = document.querySelector('[data-controller~="ruby-ui--theme-toggle"]');
          window.Stimulus.getControllerForElementAndIdentifier(element, 'ruby-ui--theme-toggle').setTheme();
        JS
      end

      assert_selector "html.dark.theme-dark"
      assert_no_selector "html.light, html.theme-light"
      assert_equal [ [ "light", "(prefers-color-scheme: light)" ], [ "dark", "(prefers-color-scheme: dark)" ] ], theme_media
      assert_equal "undefined", page.evaluate_script("typeof window.Stimulus") if block_modules
    end
  ensure
    browser&.execute_cdp("Page.removeScriptToEvaluateOnNewDocument", identifier: script["identifier"]) if script
    browser&.execute_cdp("Network.setBlockedURLs", urls: [])
    browser&.execute_cdp("Emulation.setEmulatedMedia", features: [])
  end

  test "저장소 쓰기가 차단돼도 선택한 테마와 주소창 색을 적용한다" do
    visit root_path
    page.execute_script(<<~JS)
      localStorage.theme = 'light';
      const storage = localStorage;
      Object.defineProperty(window, 'localStorage', {
        value: {
          get theme() { return storage.theme; },
          set theme(value) { throw new DOMException('Blocked', 'SecurityError'); }
        }
      });
      const element = document.querySelector('[data-controller~="ruby-ui--theme-toggle"]');
      window.Stimulus.getControllerForElementAndIdentifier(element, 'ruby-ui--theme-toggle').setTheme();
    JS

    find('footer button[aria-label="다크 모드로 전환"]').click

    assert_selector "html.dark.theme-dark"
    assert_no_selector "html.light, html.theme-light"
    assert_equal [ [ "light", "not all" ], [ "dark", "all" ] ], theme_media

    find('footer button[aria-label="라이트 모드로 전환"]').click

    assert_selector "html.light.theme-light"
    assert_no_selector "html.dark, html.theme-dark"
    assert_equal [ [ "light", "all" ], [ "dark", "not all" ] ], theme_media
    assert_equal "light", page.evaluate_script("localStorage.theme")
  end

  private

  def theme_media
    page.evaluate_script('Array.from(document.querySelectorAll(\'meta[name="theme-color"][data-theme]\'), meta => [meta.dataset.theme, meta.media])')
  end
end
