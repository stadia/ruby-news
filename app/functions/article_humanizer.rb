# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

module ArticleHumanizer
  # 윤문 응답에서 꺼낸 결과. 반영할 수 없으면 skip_reason에 사유가 있고 attributes는 비어 있다.
  # 멤버 타입: sorbet/rbi/shims/data_definitions.rbi
  Extraction = Data.define(:attributes, :skip_reason)

  # 원 요약(ArticleSchema)과 윤문(HumanMonolithAgent) 스키마가 공유하는 summary_detail 키.
  DETAIL_KEYS = %w[introduction conclusion].freeze

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

      # 비었거나 타입이 틀린 요점·상세는 키를 빼서 update!가 기존 값을 지우지 않게 한다.
      attributes = {
        summary_key: string_list(content["summary_key"]),
        summary_detail: string_map(content["summary_detail"]),
        summary_body:
      }.compact
      Extraction.new(attributes:, skip_reason: nil)
    end

    private

    #: (Symbol reason) -> Extraction
    def skipped(reason)
      Extraction.new(attributes: {}, skip_reason: reason)
    end

    # 문자열이 아니거나 공백뿐이면 nil이다. `.to_s`로 받으면 배열 등의 inspect 문자열이 저장된다.
    #: (untyped value) -> String?
    def stripped_string(value)
      value.strip.presence if value.is_a?(String)
    end

    # 모든 요소가 문자열인 배열만 받는다. 문자열이 아닌 요소(nil·숫자·중첩 배열·Hash)가
    # 하나라도 있으면 요점 전체를 버린다. 공백뿐인 문자열 요소는 제거하고, 남은 것이 없으면 nil이다.
    #: (untyped value) -> Array[String]?
    def string_list(value)
      return unless value.is_a?(Array) && value.all?(String)

      value.filter_map { stripped_string(it) }.presence
    end

    # 스키마의 두 키(DETAIL_KEYS)가 모두 있고, 모든 값이 비어 있지 않은 문자열인 Hash만
    # 받는다. 하나라도 어기면 상세 전체를 버린다. 일부만 받으면 update!가 Hash 전체를
    # 교체해 기존 값 중 빠진 키가 사라진다.
    #: (untyped value) -> Hash[String, String]?
    def string_map(value)
      return unless value.is_a?(Hash) && DETAIL_KEYS.all? { value.key?(it) }

      result = {} #: Hash[String, String]
      value.each do |key, item|
        text = stripped_string(item)
        return unless key.is_a?(String) && text

        result[key] = text
      end
      result.presence
    end
  end
end
