# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

module Articles
  module AgentRunner
    extend FunctionLogger
    # Dry::Monads[:result]은 Result::Mixin을 반환한다. 상수를 직접 extend해야
    # Sorbet이 Success/Failure 생성자를 RBI에서 해석할 수 있다.
    extend(Dry::Monads::Result::Mixin)

    class << self
      #: (article: Article, prompt: String) -> Dry::Monads::Result
      def run(article:, prompt:)
        message = ArticleAgent.new.ask(prompt)
        logger.info "Response received for article id: #{article.id}"

        if message.content.blank?
          article.discard!
          return Failure(message.finish_reason)
        end

        # ruby_llm 2.0부터 content는 JSON 문자열이고 스키마 응답 Hash는 parsed에 있다.
        # 모델이 코드펜스로 감싸거나 Hash가 아닌 JSON(배열 등)을 돌려줄 수 있어
        # AgentResponse.structured로 예외를 흡수하고 Hash가 아니면 실패로 처리한다.
        # 여기서 raise가 새면 ArticleAgentsService#call의 step이 못 잡아 파이프라인
        # 전체가 discard·후속 단계 없이 미처리 예외로 죽는다.
        content = Articles::AgentResponse.structured(message)
        unless content.is_a?(Hash)
          logger.warn "Agent response was not a Hash (#{content.class}) for article #{article.id}"
          article.discard!
          return Failure(:invalid_agent_response)
        end
        content = content.deep_stringify_keys

        apply_tags(article, content)
        normalize_summary_body(content)
        article.update!(content)

        Success(article)
      end

      private

      def apply_tags(article, content)
        return unless content["tags"].present?

        tags = Array(content.delete("tags")).filter_map do |tag|
          next unless tag.is_a?(String) || tag.is_a?(Symbol)

          tag.to_s.downcase.strip.presence
        end.uniq
        return if tags.empty?

        article.tag_list.add(*tags)
      end

      def normalize_summary_body(content)
        body = content["summary_body"]
        return if body.blank?

        content["summary_body"] = body.to_s
          .gsub("\\n", "\n")
          .gsub("\\t", "\t")
          .gsub("\\r", "\r")
          .gsub("\\\\", "\\")
          .gsub('\"', '"')
      end
    end
  end
end
