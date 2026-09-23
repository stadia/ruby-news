# frozen_string_literal: true

require "test_helper"

# 도구 인자 스키마는 모델이 보는 계약이다. ruby_llm 2.0에서 선언 DSL이 바뀌어도
# 범위 제약과 필수 인자가 그대로 전달되는지 확인한다.
class ToolParametersTest < ActiveSupport::TestCase
  test "SearchRelatedArticles는 limit를 1~10으로 제한하고 필수 인자가 없다" do
    schema = SearchRelatedArticles.new.parameters_schema.deep_stringify_keys

    assert_equal %w[article_id query limit], schema["properties"].keys
    assert_equal 1, schema.dig("properties", "limit", "minimum")
    assert_equal 10, schema.dig("properties", "limit", "maximum")
    assert_empty schema["required"]
  end

  test "GetExistingTags는 limit를 1~50으로 제한한다" do
    schema = GetExistingTags.new.parameters_schema.deep_stringify_keys

    assert_equal %w[keyword limit], schema["properties"].keys
    assert_equal 50, schema.dig("properties", "limit", "maximum")
  end

  test "ValidateSlug는 slug를 필수로 받는다" do
    schema = ValidateSlug.new.parameters_schema.deep_stringify_keys

    assert_equal [ "slug" ], schema["required"]
  end
end
