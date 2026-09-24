# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

module Articles
  module AgentResponse
    class << self
      # 코드 펜스 바깥쪽만 벗긴다. 본문 안의 펜스는 JSON 문자열 값 안에 이스케이프돼 있어 닿지 않는다.
      FENCED_JSON = /\A```(?:json)?[ \t]*\n(.*)\n```\z/m

      # ruby_llm 2.0부터 스키마 응답 Hash는 parsed에 있다. 모델이 JSON이 아닌 텍스트를
      # 돌려주면 parsed가 예외를 내므로 원문 content를 넘겨 호출부의 Hash 가드가 거르게 한다.
      # 모델이 JSON을 코드 펜스로 감싸거나 문자열로 한 번 더 인코딩하면 parsed가 String이 되므로
      # 한 번 더 풀어 본다.
      #: (RubyLLM::Message message) -> untyped
      def structured(message)
        unwrap_json(message.parsed)
      rescue JSON::ParserError
        unwrap_json(message.content)
      end

      # String 안의 JSON 객체를 꺼낸다. 풀리지 않거나 객체가 아니면 받은 값을 그대로 돌려준다.
      #: (untyped value) -> untyped
      def unwrap_json(value)
        return value unless value.is_a?(String)

        text = value.strip
        text = Regexp.last_match(1).to_s if text =~ FENCED_JSON
        decoded = JSON.parse(text)
        decoded.is_a?(Hash) ? decoded : value
      rescue JSON::ParserError
        value
      end

      # 값이 Array일 때만 문자열 배열로 정규화한다. 그 외에는 nil(호출부에서 compact 제거).
      #: (untyped value) -> Array[String]?
      def array_of_strings(value)
        return unless value.is_a?(Array)

        value.map(&:to_s).reject(&:blank?)
      end

      # 값이 Hash일 때만 값들을 문자열로 정규화한다. 그 외에는 nil(호출부에서 compact 제거).
      #: (untyped value) -> Hash[untyped, String]?
      def hash_of_strings(value)
        return unless value.is_a?(Hash)

        value.transform_values(&:to_s)
      end
    end
  end
end
