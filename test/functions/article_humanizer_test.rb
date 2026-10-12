# frozen_string_literal: true

require "test_helper"

class ArticleHumanizerTest < ActiveSupport::TestCase
  test "응답 Hash에서 윤문 필드만 정규화해 꺼낸다" do
    content = {
      "summary_key" => [ " 요점 ", "" ],
      "summary_detail" => { "introduction" => "도입", "conclusion" => "결론" },
      "summary_body" => "  본문  ",
      "metrics" => { "x" => 1 }
    }

    extraction = ArticleHumanizer.extract(content)

    assert_instance_of ArticleHumanizer::Humanized, extraction
    assert_equal(
      { summary_key: [ "요점" ], summary_detail: { "introduction" => "도입", "conclusion" => "결론" }, summary_body: "본문" },
      extraction.to_attributes
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

    assert_equal({ summary_body: "본문" }, extraction.to_attributes)
  end

  # 빈 값이나 잘못된 타입으로 update!하면 기존 요점·상세가 지워지고, 요점이 없으면 썸네일 단계도 건너뛴다.
  test "요점과 상세가 비어 있으면 해당 필드를 제외해 기존 값을 보존한다" do
    extraction = ArticleHumanizer.extract({ "summary_key" => [ "", " " ], "summary_detail" => {}, "summary_body" => "본문" })

    assert_equal({ summary_body: "본문" }, extraction.to_attributes)
  end

  # 도입·결론 중 하나가 빠졌거나, 값이 하나라도 문자열이 아니거나 비어 있으면 상세 전체를
  # 받지 않는다. 일부만 받으면 update!가 Hash 전체를 교체해 기존 도입·결론 중 빠진 쪽이 사라진다.
  test "상세 값이 문자열이 아니거나 비어 있으면 상세를 제외해 기존 값을 보존한다" do
    [
      { "introduction" => [ "a" ] },
      { "introduction" => nil },
      { "introduction" => " ", "conclusion" => "" },
      { "introduction" => "도입", "conclusion" => "" },
      { "introduction" => "도입" },
      { "conclusion" => "결론" },
      { "introduction" => 1 }
    ].each do |detail|
      extraction = ArticleHumanizer.extract({ "summary_detail" => detail, "summary_body" => "본문" })

      assert_equal({ summary_body: "본문" }, extraction.to_attributes, detail.inspect)
    end
  end

  test "상세 값은 strip해서 받는다" do
    extraction = ArticleHumanizer.extract({
      "summary_detail" => { "introduction" => " 도입 ", "conclusion" => "결론 " }, "summary_body" => "본문"
    })

    assert_equal({ summary_body: "본문", summary_detail: { "introduction" => "도입", "conclusion" => "결론" } }, extraction.to_attributes)
  end

  # 문자열이 아닌 요소가 하나라도 있으면 요점 전체를 받지 않는다. 중첩 배열·Hash는
  # inspect 문자열로 저장되고, nil·숫자는 의미 없는 문자열이 된다.
  test "요점에 문자열이 아닌 요소가 있으면 요점을 제외한다" do
    [ [ [ "a" ] ], [ { "text" => "x" } ], [ "a", 1 ] ].each do |summary_key|
      extraction = ArticleHumanizer.extract({ "summary_key" => summary_key, "summary_body" => "본문" })

      assert_equal({ summary_body: "본문" }, extraction.to_attributes, summary_key.inspect)
    end
  end

  # 윤문 필드는 Data 멤버라 오타나 다른 속성은 Ruby가 키워드 오류로 막는다.
  test "Humanized는 필드를 멤버로 읽는다" do
    extraction = ArticleHumanizer.extract({ "summary_key" => [ "요점" ], "summary_body" => "본문" })

    assert_equal "본문", extraction.summary_body
    assert_equal [ "요점" ], extraction.summary_key
    assert_nil extraction.summary_detail
    assert_raises(NoMethodError) { extraction.summary_bdy }
  end

  test "Humanized는 본문이 없거나 비었으면 만들 수 없다" do
    [ {}, { summary_key: [ "a" ] }, { summary_body: " " }, { summary_body: nil }, { summary_body: [ "본문" ] } ].each do |fields|
      assert_raises(ArgumentError, fields.inspect) { ArticleHumanizer::Humanized.build(**fields) }
    end
  end

  test "Humanized는 윤문 필드가 아닌 키를 받지 않는다" do
    error = assert_raises(ArgumentError) do
      ArticleHumanizer::Humanized.build(summary_body: "본문", title_ko: "제목")
    end
    assert_includes error.message, "title_ko"
  end

  # 빈 값이나 타입이 틀린 요점·상세를 update!에 넘기면 기존 값이 지워지거나 깨진다.
  # 받지 못한 필드는 nil로 둔다.
  test "Humanized는 비었거나 타입이 틀린 요점·상세를 받지 않는다" do
    [
      { summary_key: [] }, { summary_key: "요점" }, { summary_key: [ "a", 1 ] },
      { summary_detail: {} }, { summary_detail: "상세" }, { summary_detail: { "introduction" => 1 } }
    ].each do |fields|
      assert_raises(ArgumentError, fields.inspect) { ArticleHumanizer::Humanized.build(summary_body: "본문", **fields) }
    end
  end

  # nil은 응답에서 받지 못한 필드다. 저장할 Hash에서 빼서 기존 값을 지우지 않는다.
  test "to_attributes는 받지 못한 필드를 뺀다" do
    humanized = ArticleHumanizer::Humanized.build(summary_body: "본문", summary_key: nil)

    assert_equal({ summary_body: "본문" }, humanized.to_attributes)
  end

  # 검사를 우회해 불변식이 깨진 값을 만들 수 없게 한다. Data는 new 외에 []·allocate·#with로도
  # 인스턴스를 만들 수 있으므로 모두 막는다.
  test "Humanized와 Skipped는 build로만 만든다" do
    humanized = ArticleHumanizer.extract({ "summary_body" => "본문" })
    skipped = ArticleHumanizer::Skipped.build(:humanize_aborted)

    [
      -> { ArticleHumanizer::Humanized.new(summary_body: " ", summary_key: nil, summary_detail: nil) },
      -> { ArticleHumanizer::Humanized[summary_body: " ", summary_key: nil, summary_detail: nil] },
      -> { ArticleHumanizer::Humanized.allocate },
      -> { humanized.with(summary_body: " ") },
      -> { ArticleHumanizer::Skipped.new(reason: :typo) },
      -> { ArticleHumanizer::Skipped[reason: :typo] },
      -> { ArticleHumanizer::Skipped.allocate },
      -> { skipped.with(reason: :typo) }
    ].each_with_index do |bypass, index|
      assert_raises(NoMethodError, "bypass ##{index}") { bypass.call }
    end
  end

  test "Humanized의 필드와 to_attributes는 안쪽 문자열까지 얼어 있다" do
    extraction = ArticleHumanizer.extract({
      "summary_key" => [ "요점" ],
      "summary_detail" => { "introduction" => "도입", "conclusion" => "결론" },
      "summary_body" => "본문"
    })

    assert_predicate extraction.summary_key, :frozen?
    assert_predicate extraction.summary_key.first, :frozen?
    assert_predicate extraction.summary_detail["introduction"], :frozen?
    assert_predicate extraction.to_attributes, :frozen?
    assert_raises(FrozenError) { extraction.summary_key.first << "변조" }
  end

  # 얼리는 것은 복사본이다. 호출자가 넘긴 값은 그대로 둔다.
  test "Humanized.build는 넘겨받은 값을 얼리지 않는다" do
    summary_key = [ +"요점" ]
    ArticleHumanizer::Humanized.build(summary_key:, summary_body: +"본문")

    assert_not_predicate summary_key, :frozen?
    assert_not_predicate summary_key.first, :frozen?
  end

  # 사유 집합을 닫아 두어 오타가 난 사유가 조용히 로그에만 남지 않게 한다.
  test "Skipped는 정해진 사유만 받는다" do
    ArticleHumanizer::SKIP_REASONS.each do |reason|
      assert_equal reason, ArticleHumanizer::Skipped.build(reason).reason
    end
    assert_raises(ArgumentError) { ArticleHumanizer::Skipped.build(:humanize_abortd) }
    assert_raises(ArgumentError) { ArticleHumanizer::Skipped.build(nil) }
  end

  test "Skipped#aborted?는 과윤문 롤백일 때만 참이다" do
    assert_predicate ArticleHumanizer::Skipped.build(:humanize_aborted), :aborted?
    assert_not_predicate ArticleHumanizer::Skipped.build(:humanize_blank_body), :aborted?
  end

  private

  def assert_skipped(reason, extraction)
    assert_instance_of ArticleHumanizer::Skipped, extraction
    assert_equal reason, extraction.reason
  end
end
