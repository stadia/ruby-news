# frozen_string_literal: true

require "test_helper"

class Articles::AgentResponseTest < ActiveSupport::TestCase
  def llm_message(content)
    RubyLLM::Message.new(role: :assistant, content:)
  end

  test "structured는 JSON 응답을 Hash로 돌려준다" do
    assert_equal({ "title" => "제목" }, Articles::AgentResponse.structured(llm_message('{"title":"제목"}')))
  end

  # 호출부는 Hash가 아니면 갱신하지 않는다. 예외 대신 원문을 넘겨 그 가드가 거르게 한다.
  test "structured는 JSON이 아닌 응답이면 원문 문자열을 돌려준다" do
    raw = "```json\n{\"title\":\"제목\"}\n```"

    assert_equal raw, Articles::AgentResponse.structured(llm_message(raw))
  end

  # JSON.parse 자체는 배열/스칼라도 성공시킨다. structured는 JSON::ParserError만 잡으므로
  # 이 경우 파싱된 값을 그대로 돌려주고, Hash 여부 판단은 호출부의 몫으로 남긴다.
  test "structured는 유효하지만 Hash가 아닌 JSON이면 파싱된 값을 그대로 돌려준다" do
    assert_equal([ "ruby", "rails" ], Articles::AgentResponse.structured(llm_message('["ruby","rails"]')))
  end

  test "array_of_strings는 배열을 빈 값 없는 문자열 배열로 정규화한다" do
    assert_equal [ "1", "요점" ], Articles::AgentResponse.array_of_strings([ 1, "", "요점", nil ])
  end

  test "array_of_strings는 배열이 아니면 nil을 돌려준다" do
    assert_nil Articles::AgentResponse.array_of_strings("summary_key")
  end

  test "hash_of_strings는 해시의 값을 문자열로 정규화한다" do
    assert_equal({ "introduction" => "1" }, Articles::AgentResponse.hash_of_strings({ "introduction" => 1 }))
  end

  test "hash_of_strings는 해시가 아니면 nil을 돌려준다" do
    assert_nil Articles::AgentResponse.hash_of_strings("summary_detail")
  end
end
