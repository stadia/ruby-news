# frozen_string_literal: true

require "test_helper"

# 왕복 한 번이 비싼 경로(#1108)에서 첫 화면 전에 받는 자산의 직렬 왕복을 늘리지 않도록 고정한다.
class RenderBlockingAssetsTest < ActionDispatch::IntegrationTest
  # 렌더 차단 스타일시트의 전부와 순서. tokens.css는 lexxy-variables가 tailwind 뒤에 온다고 전제한다.
  STYLESHEETS = %w[tailwind lexxy-variables lexxy-content lexxy-editor].freeze
  # importmap-rails 자체 preload(application.js 그래프) + layout의 컨트롤러 진입 모듈.
  MODULE_PRELOADS = %w[
    application turbo.min stimulus.min stimulus-loading lexxy.min activestorage.esm
    controllers/index controllers/application controllers/page_loader_controller
  ].freeze
  # production.rb와 같은 형태: ruby-news.jp만 same-origin, 나머지는 asset host.
  PRODUCTION_ASSET_HOST = ->(_source, request = nil) { request&.host == "ruby-news.jp" ? nil : "https://assets.example.test" }

  def visit_root(host = nil)
    host!(host) if host
    get root_path

    assert_response :success
    Nokogiri::HTML(response.body).at("head").tap { assert it }
  end

  def asset_name(href)
    URI(href).path.delete_prefix("/assets/").sub(/-\h+\.(css|js)\z/, "")
  end

  def stylesheets(head)
    head.css('link[rel="stylesheet"]').map { it["href"] }.reject { it.include?("fonts.googleapis.com") }
  end

  def modulepreloads(head) = head.css('link[rel="modulepreload"]').map { it["href"] }

  def importmap_imports(head) = JSON.parse(head.at('script[type="importmap"]').text).fetch("imports")

  def with_production_asset_host
    original = ActionController::Base.asset_host
    ActionController::Base.asset_host = PRODUCTION_ASSET_HOST
    Rails.application.importmap.send(:clear_cache)
    yield
  ensure
    ActionController::Base.asset_host = original
    Rails.application.importmap.send(:clear_cache)
  end

  test "렌더 차단 스타일시트는 tailwind와 lexxy 3종뿐이고 이 순서다" do
    assert_equal STYLESHEETS, stylesheets(visit_root).map { asset_name(it) }
  end

  test "modulepreload는 정해진 모듈만 받는다" do
    assert_equal MODULE_PRELOADS.sort, modulepreloads(visit_root).map { asset_name(it) }.sort
  end

  test "레이아웃의 진입 모듈 목록은 controllers/index.js의 정적 import와 맞는다" do
    index_imports = Rails.root.join("app/javascript/controllers/index.js").read.scan(%r{from "(controllers/[^"]+)"}).flatten

    assert_equal [ "controllers", *index_imports ].sort, Components::Layout::CONTROLLER_ENTRY_MODULES.sort
  end

  test "asset_host가 host마다 달라도 진입 모듈 preload URL은 importmap URL과 같다" do
    with_production_asset_host do
      # importmap JSON은 첫 요청 host로 캐시되므로 양쪽 순서를 모두 본다.
      [ %w[www.example.com ruby-news.jp], %w[ruby-news.jp www.example.com] ].each do |hosts|
        Rails.application.importmap.send(:clear_cache)
        hosts.each do |host|
          head = visit_root(host)
          imports = importmap_imports(head)

          Components::Layout::CONTROLLER_ENTRY_MODULES.each do |name|
            assert_includes modulepreloads(head), imports.fetch(name), "#{host}: #{name} preload URL이 importmap과 다르다"
          end
        end
      end
    end
  end
end
