# frozen_string_literal: true

require "test_helper"

# 왕복 한 번이 비싼 경로(#1108)에서 첫 화면 전에 받는 자산의 직렬 왕복을 늘리지 않도록 고정한다.
class RenderBlockingAssetsTest < ActionDispatch::IntegrationTest
  setup do
    get root_path
    @head = Nokogiri::HTML(response.body).at("head")
  end

  def stylesheet_hrefs
    @head.css('link[rel="stylesheet"]').map { it["href"] }.grep(%r{/assets/})
  end

  def modulepreloads
    @head.css('link[rel="modulepreload"]').map { it["href"] }
  end

  test "lightgallery.css는 head에서 렌더 차단으로 로드하지 않는다" do
    assert_empty stylesheet_hrefs.grep(/lightgallery/)
  end

  test "lexxy CSS는 @import 체인(lexxy.css) 대신 개별 파일을 직접 링크한다" do
    assert_empty stylesheet_hrefs.grep(%r{/lexxy-[0-9a-f]+\.css})
    %w[lexxy-variables lexxy-content lexxy-editor].each do |name|
      assert_equal 1, stylesheet_hrefs.grep(%r{/#{name}-}).size, "#{name}.css가 한 번 링크되어야 한다"
    end
  end

  test "application.js가 정적으로 import하는 컨트롤러 진입 모듈은 modulepreload한다" do
    %w[controllers/index- controllers/application- controllers/page_loader_controller-].each do |path|
      assert modulepreloads.any? { it.include?(path) }, "#{path} modulepreload 누락"
    end
  end

  test "앱이 import하지 않는 reactionview는 modulepreload하지 않는다" do
    assert_empty modulepreloads.grep(/reactionview/)
  end
end
