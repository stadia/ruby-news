# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

require "ruby_llm/schema"

class ArticleJapaneseSchema < Schematist::Schema
  string :title_ja, description: "한국어 제목의 의미를 살린 자연스러운 일본어 제목"

  array :summary_key_ja, of: :string, description: "한국어 핵심 요약을 일본어로 번역한 항목 3개 (각 60자 이상)"

  object :summary_detail_ja, description: "상세 요약 일본어 번역 (서론/결론)" do
    string :introduction, description: "도입부 일본어 번역 (200-300자)"
    string :conclusion, description: "결론 일본어 번역 (200-300자)"
  end

  string :summary_body_ja, description: "본론 일본어 번역 마크다운 (1000자 이상, h3 이하 헤더만 사용)"
end
