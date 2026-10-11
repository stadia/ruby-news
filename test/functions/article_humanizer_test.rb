# frozen_string_literal: true

require "test_helper"

class ArticleHumanizerTest < ActiveSupport::TestCase
  test "응답 Hash에서 윤문 필드만 정규화해 꺼낸다" do
    content = {
      "summary_key" => [ "요점", "" ],
      "summary_detail" => { "a" => "설명" },
      "summary_body" => "  본문  ",
      "metrics" => { "x" => 1 }
    }

    assert_equal(
      { summary_key: [ "요점" ], summary_detail: { "a" => "설명" }, summary_body: "본문" },
      ArticleHumanizer.extract(content)
    )
  end

  # String에 ["summary_body"]를 부르면 부분문자열 매칭으로 키 이름이 본문을 덮는다.
  test "응답이 Hash가 아니면 빈 Hash를 돌려준다" do
    assert_equal({}, ArticleHumanizer.extract("summary_body"))
  end

  test "과윤문으로 중단된 응답은 빈 Hash를 돌려준다" do
    assert_equal({}, ArticleHumanizer.extract({ "over_polish_aborted" => true, "summary_body" => "x" }))
  end
end
