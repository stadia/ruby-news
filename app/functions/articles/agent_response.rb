# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

module Articles
  module AgentResponse
    class << self
      # ruby_llm 2.0부터 스키마 응답 Hash는 parsed에 있다. 모델이 JSON이 아닌 텍스트를
      # 돌려주면 parsed가 예외를 내므로 원문 content를 넘겨 호출부의 Hash 가드가 거르게 한다.
      #: (RubyLLM::Message message) -> untyped
      def structured(message)
        message.parsed
      rescue JSON::ParserError
        message.content
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
