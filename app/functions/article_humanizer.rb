# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

module ArticleHumanizer
  # 윤문 응답에서 꺼낸 결과. 반영할 수 없으면 skip_reason에 사유가 있고 attributes는 비어 있다.
  # 멤버 타입: sorbet/rbi/shims/data_definitions.rbi
  Extraction = Data.define(:attributes, :skip_reason)

  class << self
    #: (Article article) -> String
    def prompt(article)
      keys = Array(article.summary_key).map(&:to_s).reject(&:blank?)
      details = article.summary_detail.to_h.transform_values(&:to_s)
      body = article.summary_body.to_s

      payload = {
        summary_key: keys,
        summary_detail: details,
        summary_body: body
      }

      <<~PROMPT
        다음 JSON의 각 필드를 사람이 쓴 것처럼 윤문하여 동일한 구조로 반환하라.
        #{JSON.pretty_generate(payload)}
      PROMPT
    end

    # content가 Hash가 아니면(모델 응답이 JSON이 아니어서 AgentResponse.structured가 String을 넘긴 경우)
    # content["summary_body"]는 String#[] 부분문자열 매칭이 되어 키 이름 자체를 돌려준다.
    # 그대로 두면 본문이 "summary_body"라는 글자로 덮이므로 반드시 Hash만 받는다.
    #
    # 반영할 수 없는 응답은 사유를 skip_reason에 담는다. 과윤문 롤백(:humanize_aborted)은
    # 모델의 정상 판단이고, 나머지는 응답이 계약을 어긴 경우다.
    #: (untyped content) -> Extraction
    def extract(content)
      return skipped(:humanize_invalid_response) unless content.is_a?(Hash)
      return skipped(:humanize_aborted) if content["over_polish_aborted"]

      summary_body = stripped_string(content["summary_body"])
      return skipped(:humanize_blank_body) unless summary_body

      # 빈 요점·상세는 키를 빼서 update!가 기존 값을 지우지 않게 한다.
      attributes = {
        summary_key: string_list(content["summary_key"]),
        summary_detail: Articles::AgentResponse.hash_of_strings(content["summary_detail"]).presence,
        summary_body:
      }.compact
      Extraction.new(attributes:, skip_reason: nil)
    end

    private

    #: (Symbol reason) -> Extraction
    def skipped(reason)
      Extraction.new(attributes: {}, skip_reason: reason)
    end

    # 문자열이 아니면 nil이다. `.to_s`로 받으면 배열 등의 inspect 문자열이 저장된다.
    #: (untyped value) -> String?
    def stripped_string(value)
      value.strip.presence if value.is_a?(String)
    end

    # 모든 요소가 문자열인 배열만 받는다. 중첩 배열·Hash 요소가 섞이면 요점 전체를 버린다.
    #: (untyped value) -> Array[String]?
    def string_list(value)
      return unless value.is_a?(Array) && value.all?(String)

      value.filter_map { stripped_string(it) }.presence
    end
  end
end
