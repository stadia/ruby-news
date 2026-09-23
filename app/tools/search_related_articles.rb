# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

class SearchRelatedArticles < RubyLLM::Tool
  description "관련 기사를 검색한다. article_id가 주어지면 벡터 유사도로, query가 주어지면 제목 텍스트로 검색한다."

  parameters type: "object",
    properties: {
      article_id: {
        type: "integer",
        description: "현재 기사 ID (embedding 기반 유사도 검색용, 자기 자신 제외)"
      },
      query: {
        type: "string",
        description: "제목 텍스트 검색 키워드"
      },
      limit: {
        type: "integer",
        description: "최대 반환 건수",
        minimum: 1,
        maximum: 10,
        default: 3
      }
    },
    required: []

  def execute(article_id: nil, query: nil, limit: 3)
    return { error: "article_id 또는 query가 필요합니다" } if article_id.nil? && query.blank?

    limit = [ [ limit.to_i, 1 ].max, 10 ].min

    if article_id
      search_by_embedding(article_id, query, limit)
    else
      search_by_text(query, limit)
    end
  rescue StandardError => e
    { error: e.message }
  end

  private

  def search_by_embedding(article_id, query, limit)
    article = Article.find_by(id: article_id)
    return { error: "기사를 찾을 수 없습니다 (id=#{article_id})" } unless article

    unless article.embedding.present?
      return query.present? ? search_by_text(query, limit) : []
    end

    Article.kept.confirmed
           .where.not(id: article.id)
           .nearest_neighbors(:embedding, article.embedding, distance: "cosine")
           .limit(limit)
           .select(:id, :title_ko, :slug, :summary_key)
           .map { format_result(it) }
  end

  def search_by_text(query, limit)
    ids = Articles::HybridSearch.run(query:, limit:, mmr: true)
    return [] if ids.empty?

    Article.kept.confirmed.where(id: ids).in_order_of(:id, ids)
           .select(:id, :title_ko, :slug, :summary_key)
           .map { format_result(it) }
  end

  def format_result(article)
    { title_ko: article.title_ko, slug: article.slug, path: "/articles/#{article.slug}", summary_key: article.summary_key }
  end
end
