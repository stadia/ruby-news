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

  test "요점과 상세의 타입이 잘못됐으면 해당 필드를 제외한다" do
    assert_equal(
      { summary_body: "본문" },
      ArticleHumanizer.extract({ "summary_key" => "요점", "summary_detail" => "설명", "summary_body" => "본문" })
    )
  end

  test "누락된 필드와 공백 본문은 결과에서 제외한다" do
    assert_equal(
      { summary_key: [ "a" ] },
      ArticleHumanizer.extract({ "summary_key" => [ "a" ], "summary_body" => "   " })
    )
    assert_equal({}, ArticleHumanizer.extract({}))
  end
end
