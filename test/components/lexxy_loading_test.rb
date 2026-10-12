# frozen_string_literal: true

require "test_helper"

# lexxy 로딩 레이어가 eager 전역 로딩을 유지하는지 고정(JS는 eager import·preload,
# CSS는 head에서 variables/content/editor를 직접 링크).
# lazy/조건부 로딩(동적 import, preload: false, 페이지별 asset_tags, turbo_permanent
# 밴드에이드)이 재도입되면 빈 화면 회귀가 되돌아오므로 이를 방지한다.
class LexxyLoadingTest < ActiveSupport::TestCase
  APPLICATION_JS = Rails.root.join("app/javascript/application.js").read
  IMPORTMAP = Rails.root.join("config/importmap.rb").read
  LAYOUT = Rails.root.join("app/components/layout.rb").read
  SITE_CSS = Rails.root.join("app/assets/tailwind/site.css").read

  test "application.js는 lexxy를 최상위에서 eager import한다(동적 import 아님)" do
    assert_match(/^import "lexxy";$/, APPLICATION_JS)
    refute_match(/import\("lexxy"\)/, APPLICATION_JS)
  end

  test "importmap은 lexxy를 preload한다(preload: false 아님)" do
    assert_match(/^pin "lexxy", to: "lexxy\.min\.js"$/, IMPORTMAP)
    refute_match(/pin "lexxy".*preload: false/, IMPORTMAP)
  end

  test "layout은 head에서 lexxy CSS를 전역 로드한다" do
    assert_match(/stylesheet_link_tag "lexxy-variables", "lexxy-content", "lexxy-editor"/, LAYOUT)
  end

  test "Components::Base는 lexxy_editor_asset_tags를 정의하지 않는다" do
    refute Components::Base.private_method_defined?(:lexxy_editor_asset_tags)
  end

  # 커스텀 엘리먼트 업그레이드 전(JS 실행 전) <lexxy-editor>는 내부 content div가
  # 없어 0 높이로 접혔다가, JS 마운트 후 5줄 높이로 펼쳐진다("시간차로 그려짐").
  # 컴포저 에디터 자체에 마운트 후 높이와 같은 min-block-size를 예약해 이 시프트를
  # 없앤다. 예약이 빠지면 얇은 선 → 5줄 점프 회귀가 되돌아온다.
  test "컴포저 lexxy 에디터는 업그레이드 전 높이를 예약해 레이아웃 시프트를 막는다" do
    assert_match(
      /\.post-composer-editor\b[^}]*min-block-size:/m,
      SITE_CSS,
      "post-composer-editor에 min-block-size 높이 예약이 있어야 한다"
    )
  end
end
