# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

class ArticleSchema < Schematist::Schema
  string :title_ko, description: "원문 제목의 의미를 살린 자연스러운 한국어 제목"

  array :summary_key, of: :string, description: "가장 중요한 내용 순으로 정렬된 핵심 요약 3개 (각 60자 이상)"

  object :summary_detail, description: "상세 요약 (서론/결론)" do
    string :introduction, description: "배경과 맥락을 바로 전달 (200-300자)"
    string :conclusion, description: "실질적 시사점 또는 핵심 takeaway (200-300자)"
  end

  string :summary_body, description: "핵심 내용과 세부사항을 다루는 마크다운 본론 (1000자 이상, h3 이하 헤더만 사용)"

  array :tags, of: :string, description: "본문에서 추출한 구체적 핵심 키워드 (최대 3개, 소문자 snake_case)"

  boolean :is_related, description: "Ruby, Rails, Gem, Ruby 개발 도구/커뮤니티와의 관련 여부"
end
