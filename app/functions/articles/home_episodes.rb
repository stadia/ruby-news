# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

module Articles
  module HomeEpisodes
    # shortcut: 확인된 URL만 묶는다. 등록 비용이 커지면 수집 시 공식 에피소드 ID를 저장한다.
    SOURCES = YAML.load_file(Rails.root.join("config/home_episode_sources.yml")).map(&:freeze).freeze

    class << self
      #: (ActiveRecord::Relation scope) -> ActiveRecord::Relation
      def representatives(scope)
        urls = SOURCES.flatten
        lookup = scope.except(:includes, :preload, :eager_load)
        candidates = lookup.where(url: urls).or(lookup.where(origin_url: urls))
                          .reorder(created_at: :desc, id: :desc).pluck(:id, :url, :origin_url)
        excluded_ids = SOURCES.flat_map do |sources|
          candidates.select { |_, url, origin_url| sources.include?(url) || sources.include?(origin_url) }
                    .drop(1).map(&:first)
        end
        scope.where.not(id: excluded_ids)
      end

      #: (Article article) -> Array[String]
      def source_urls(article)
        SOURCES.find { |sources| sources.include?(article.url) || sources.include?(article.origin_url) } || []
      end
    end
  end
end
