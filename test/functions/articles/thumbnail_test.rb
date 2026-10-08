# frozen_string_literal: true

require "test_helper"

class Articles::ThumbnailTest < ActiveSupport::TestCase
  ONE_PX_PNG = Base64.decode64(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
  )

  # OpenRouter 이미지 API는 b64_json을 RubyLLM::Image(data:)로 돌려준다.
  test "OpenRouter openai/gpt-image-2로 그린 이미지를 썸네일로 붙인다" do
    article = articles(:ruby_article)
    article.update!(summary_key: [ "요점" ])
    image = RubyLLM::Image.new(data: Base64.strict_encode64(ONE_PX_PNG), mime_type: "image/png")
    called_with = nil
    paint = ->(prompt, **opts) { called_with = opts.merge(prompt:); image }

    RubyLLM.stub(:paint, paint) { Articles::Thumbnail.generate(article) }

    assert_predicate article.thumbnail, :attached?
    assert_equal "image/png", article.thumbnail.content_type
    assert_equal "openai/gpt-image-2", called_with[:model]
    assert_equal :openrouter, called_with[:provider]
    assert_includes called_with[:prompt], "1. 요점"
  end

  test "summary_key가 없으면 이미지를 생성하지 않는다" do
    article = articles(:ruby_article)
    article.update!(summary_key: [])

    RubyLLM.stub(:paint, ->(*) { flunk "should not paint" }) { Articles::Thumbnail.generate(article) }

    assert_not_predicate article.thumbnail, :attached?
  end
end
