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
    end
  end
end
