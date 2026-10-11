# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

module ArticleHumanizer
  extend FunctionLogger

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
    #: (untyped content) -> Hash[Symbol, untyped]
    def extract(content)
      unless content.is_a?(Hash)
        logger.warn "Humanize response was not a Hash (#{content.class}); skipping update"
        return {}
      end

      return {} if content["over_polish_aborted"]

      {
        summary_key: Articles::AgentResponse.array_of_strings(content["summary_key"]),
        summary_detail: Articles::AgentResponse.hash_of_strings(content["summary_detail"]),
        summary_body: content["summary_body"].to_s.strip.presence
      }.compact
    end
  end
end
