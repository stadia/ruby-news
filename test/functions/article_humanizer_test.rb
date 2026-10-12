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

  # 모델은 롤백하면서 본문을 비워 돌려줄 수 있다. 이때도 정상 판단(:humanize_aborted)이다.
  test "과윤문 중단이 본문 비어 있음보다 우선한다" do
    assert_skipped :humanize_aborted, ArticleHumanizer.extract({ "over_polish_aborted" => true, "summary_body" => "" })
    assert_skipped :humanize_aborted, ArticleHumanizer.extract({ "over_polish_aborted" => true })
  end

  test "Hash가 아닌 응답은 모두 :humanize_invalid_response로 건너뛴다" do
    [ nil, [], [ "summary_body" ], 1 ].each do |content|
      assert_skipped :humanize_invalid_response, ArticleHumanizer.extract(content)
    end
  end

  test "본문이 비었거나 없으면 :humanize_blank_body로 건너뛴다" do
    assert_skipped :humanize_blank_body, ArticleHumanizer.extract({ "summary_key" => [ "a" ], "summary_body" => "   " })
    assert_skipped :humanize_blank_body, ArticleHumanizer.extract({})
  end

  # `.to_s`로 받으면 배열의 inspect 문자열이 summary_body를 덮는다.
  test "본문이 문자열이 아니면 :humanize_blank_body로 건너뛴다" do
    assert_skipped :humanize_blank_body, ArticleHumanizer.extract({ "summary_body" => [ "a", "b" ] })
  end

  test "요점과 상세의 타입이 잘못됐으면 해당 필드를 제외한다" do
    extraction = ArticleHumanizer.extract({ "summary_key" => "요점", "summary_detail" => "설명", "summary_body" => "본문" })

    assert_equal({ summary_body: "본문" }, extraction.attributes)
  end

  # 빈 값이나 잘못된 타입으로 update!하면 기존 요점·상세가 지워지고, 요점이 없으면 썸네일 단계도 건너뛴다.
  test "요점과 상세가 비어 있으면 해당 필드를 제외해 기존 값을 보존한다" do
    extraction = ArticleHumanizer.extract({ "summary_key" => [ "", " " ], "summary_detail" => {}, "summary_body" => "본문" })

    assert_equal({ summary_body: "본문" }, extraction.attributes)
  end

  # 값이 하나라도 문자열이 아니거나 비어 있으면 상세 전체를 받지 않는다. 일부만 받으면
  # update!가 Hash 전체를 교체해 기존 도입·결론 중 빠진 쪽이 사라진다.
  test "상세 값이 문자열이 아니거나 비어 있으면 상세를 제외해 기존 값을 보존한다" do
    [
      { "introduction" => [ "a" ] },
      { "introduction" => nil },
      { "introduction" => " ", "conclusion" => "" },
      { "introduction" => "도입", "conclusion" => "" },
      { "introduction" => 1 }
    ].each do |detail|
      extraction = ArticleHumanizer.extract({ "summary_detail" => detail, "summary_body" => "본문" })

      assert_equal({ summary_body: "본문" }, extraction.attributes, detail.inspect)
    end
  end

  test "상세 값은 strip해서 받는다" do
    extraction = ArticleHumanizer.extract({ "summary_detail" => { "introduction" => " 도입 " }, "summary_body" => "본문" })

    assert_equal({ summary_body: "본문", summary_detail: { "introduction" => "도입" } }, extraction.attributes)
  end

  # 문자열이 아닌 요소가 하나라도 있으면 요점 전체를 받지 않는다. 중첩 배열·Hash는
  # inspect 문자열로 저장되고, nil·숫자는 의미 없는 문자열이 된다.
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
