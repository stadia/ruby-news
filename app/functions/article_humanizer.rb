# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

module ArticleHumanizer
  # extract의 결과는 반영(Humanized)과 건너뜀(Skipped) 중 하나다.
  # 멤버 타입: sorbet/rbi/shims/data_definitions.rbi
  Humanized = Data.define(:attributes)
  Skipped = Data.define(:reason)

  # 원 요약(ArticleSchema)과 윤문(HumanMonolithAgent) 스키마가 공유하는 summary_detail 키.
  DETAIL_KEYS = %w[introduction conclusion].freeze
  # 윤문이 갱신할 수 있는 Article 속성. Humanized#attributes는 이 키만 갖는다.
  ATTRIBUTE_KEYS = %i[summary_key summary_detail summary_body].freeze

  # 모델이 과윤문을 스스로 롤백한 정상 판단. 나머지 사유는 응답이 계약을 어긴 경우다.
  ABORTED = :humanize_aborted
  SKIP_REASONS = [ ABORTED, :humanize_invalid_response, :humanize_blank_body ].freeze

  # 반영할 윤문 필드. update!에 그대로 넘기므로 본문이 반드시 있고, 다른 속성은 받지 않는다.
  # 불변식을 build에서 검사하도록 new는 막는다. Sorbet이 Data.define의 initialize 재정의를
  # 허용하지 않아 생성자 대신 팩토리를 쓴다.
  class Humanized
    private_class_method :new

    class << self
      #: (Hash[Symbol, untyped] attributes) -> Humanized
      def build(attributes)
        unknown = attributes.keys - ATTRIBUTE_KEYS
        raise ArgumentError, "unknown humanized attributes: #{unknown.inspect}" if unknown.any?

        body = attributes[:summary_body]
        raise ArgumentError, "summary_body is required" unless body.is_a?(String) && body.strip.present?

        new(attributes: attributes.transform_values(&:freeze).freeze)
      end
    end
  end

  # 반영하지 않은 사유. 오타가 조용히 로그에만 남지 않도록 SKIP_REASONS만 받는다.
  class Skipped
    private_class_method :new

    class << self
      #: (Symbol reason) -> Skipped
      def build(reason)
        raise ArgumentError, "unknown humanize skip reason: #{reason.inspect}" unless SKIP_REASONS.include?(reason)

        new(reason:)
      end
    end

    #: () -> bool
    def aborted? = reason == ABORTED
  end

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
    # 반영할 수 없는 응답은 사유와 함께 Skipped로 돌려준다.
    #: (untyped content) -> (Humanized | Skipped)
    def extract(content)
      return Skipped.build(:humanize_invalid_response) unless content.is_a?(Hash)
      return Skipped.build(ABORTED) if content["over_polish_aborted"]

      summary_body = stripped_string(content["summary_body"])
      return Skipped.build(:humanize_blank_body) unless summary_body

      # 비었거나 타입이 틀린 요점·상세는 키를 빼서 update!가 기존 값을 지우지 않게 한다.
      attributes = {
        summary_key: string_list(content["summary_key"]),
        summary_detail: string_map(content["summary_detail"]),
        summary_body:
      }.compact
      Humanized.build(attributes)
    end

    private

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
