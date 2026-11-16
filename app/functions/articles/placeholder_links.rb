# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

module Articles
  # 요약 모델이 관련 기사 링크의 주소를 example.com 자리표시자로 쓰는 경우를 고친다(#1161).
  # 링크 텍스트는 관련 기사 검색 결과의 제목이므로, 실제 기사로 확정되면 상대 경로로 잇고
  # 확정할 수 없으면 링크만 지우고 문구를 남긴다. 코드 예시 속 example.com은 건드리지 않는다.
  module PlaceholderLinks
    CODE = /(```.*?```|~~~.*?~~~|`[^`\n]+`)/m
    URL = %r{\s*https?://(?:www\.)?example\.(?:com|org|net)(/[^\s)）]*)?\s*}
    ARTICLE_PATH = %r{\A/articles/([^/?#]+)/?\z}
    # [패턴, 확정하지 못했을 때 남길 문구 형식]. 일본어 번역은 링크를 『제목』（주소）로 바꾸기도 한다.
    PATTERNS = [
      [ /\[([^\]\n]+)\]\(#{URL}\)/, "%s" ],
      [ /『([^』\n]+)』（#{URL}）/, "『%s』" ],
      [ /\[([^\]\n]+)\]（#{URL}）/, "%s" ]
    ].freeze
    ATTRIBUTES = %w[summary_body summary_body_ja].freeze
    Change = Data.define(:article_id, :slug, :attribute, :before, :after)

    class << self
      # 이미 저장된 기사를 고친다(#1161 데이터 정정). write: false면 바꿀 내용만 돌려준다.
      # 저장은 update_columns로 한다. 요약 변경으로 윤문 상태가 대기로 되돌아가 재윤문되지
      # 않도록 콜백을 건너뛰고, 캐시 키가 바뀌도록 updated_at만 함께 쓴다.
      #: (write: bool) -> Array[Change]
      def repair_all(write:)
        condition = ATTRIBUTES.map { "#{it} ~ 'example\\.(com|org|net)'" }.join(" OR ")
        Article.where(condition).select(:id, :slug, *ATTRIBUTES).find_each.flat_map do |article|
          changes = ATTRIBUTES.filter_map do |attribute|
            before = article[attribute]
            after = repair(before)
            Change.new(article_id: article.id, slug: article.slug, attribute:, before:, after:) if after != before
          end
          article.update_columns(changes.to_h { [ it.attribute, it.after ] }.merge(updated_at: Time.current)) if write && changes.any?
          changes
        end
      end

      #: (String? text) -> String?
      def repair(text)
        return text if text.blank?

        text.split(CODE).each_with_index.map { |part, index| index.odd? ? part : repair_prose(part) }.join
      end

      private

      #: (String prose) -> String
      def repair_prose(prose)
        PATTERNS.reduce(prose) do |result, (pattern, fallback)|
          result.gsub(pattern) do
            label = Regexp.last_match(1).to_s
            path = resolve(label, Regexp.last_match(2).to_s)
            path ? "[#{label}](#{path})" : format(fallback, label)
          end
        end
      end

      #: (String label, String path) -> String?
      def resolve(label, path)
        if (slug = path[ARTICLE_PATH, 1])
          return "/articles/#{slug}" if Article.kept.exists?(slug:)
        elsif path.delete_suffix("/").empty?
          slugs = Article.kept.where(title_ko: label).or(Article.kept.where(title_ja: label)).limit(2).pluck(:slug)
          return "/articles/#{slugs.first}" if slugs.one? && slugs.first.present?
        end
        nil
      end
    end
  end
end
