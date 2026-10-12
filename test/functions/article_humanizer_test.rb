# frozen_string_literal: true

require "test_helper"

class ArticleHumanizerTest < ActiveSupport::TestCase
  test "응답 Hash에서 윤문 필드만 정규화해 꺼낸다" do
    content = {
      "summary_key" => [ " 요점 ", "" ],
      "summary_detail" => { "a" => "설명" },
      "summary_body" => "  본문  ",
      "metrics" => { "x" => 1 }
    }

    extraction = ArticleHumanizer.extract(content)

    assert_nil extraction.skip_reason
    assert_equal(
      { summary_key: [ "요점" ], summary_detail: { "a" => "설명" }, summary_body: "본문" },
      extraction.attributes
    )
  end

  # String에 ["summary_body"]를 부르면 부분문자열 매칭으로 키 이름이 본문을 덮는다.
  test "응답이 Hash가 아니면 :humanize_invalid_response로 건너뛴다" do
    assert_skipped :humanize_invalid_response, ArticleHumanizer.extract("summary_body")
  end

  # 모델이 과윤문을 스스로 롤백한 것은 정상 결과라 응답 오류와 사유를 나눈다.
  test "과윤문으로 중단된 응답은 :humanize_aborted로 건너뛴다" do
    assert_skipped :humanize_aborted, ArticleHumanizer.extract({ "over_polish_aborted" => true, "summary_body" => "x" })
  end

  test "본문이 비었거나 없으면 :humanize_blank_body로 건너뛴다" do
    assert_skipped :humanize_blank_body, ArticleHumanizer.extract({ "summary_key" => [ "a" ], "summary_body" => "   " })
    assert_skipped :humanize_blank_body, ArticleHumanizer.extract({})
  end

  # `.to_s`로 받으면 배열의 inspect 문자열이 기사 본문을 덮는다.
  test "본문이 문자열이 아니면 :humanize_blank_body로 건너뛴다" do
    assert_skipped :humanize_blank_body, ArticleHumanizer.extract({ "summary_body" => [ "a", "b" ] })
  end

  test "요점과 상세의 타입이 잘못됐으면 해당 필드를 제외한다" do
    extraction = ArticleHumanizer.extract({ "summary_key" => "요점", "summary_detail" => "설명", "summary_body" => "본문" })

    assert_equal({ summary_body: "본문" }, extraction.attributes)
  end

  # 빈 값으로 update!하면 기존 요점·상세가 지워지고, 요점이 없으면 썸네일 단계도 건너뛴다.
  test "요점과 상세가 비어 있으면 해당 필드를 제외해 기존 값을 보존한다" do
    extraction = ArticleHumanizer.extract({ "summary_key" => [ "", " " ], "summary_detail" => {}, "summary_body" => "본문" })

    assert_equal({ summary_body: "본문" }, extraction.attributes)
  end

  # 중첩 배열이나 Hash 요소는 inspect 문자열로 저장되므로 요점 전체를 받지 않는다.
  test "요점에 문자열이 아닌 요소가 있으면 요점을 제외한다" do
    [ [ [ "a" ] ], [ { "text" => "x" } ], [ "a", 1 ] ].each do |summary_key|
      extraction = ArticleHumanizer.extract({ "summary_key" => summary_key, "summary_body" => "본문" })

      assert_equal({ summary_body: "본문" }, extraction.attributes, summary_key.inspect)
    end
  end

  private

  def assert_skipped(reason, extraction)
    assert_equal reason, extraction.skip_reason
    assert_equal({}, extraction.attributes)
  end
end
