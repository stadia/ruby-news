# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

class ValidateSlug < RubyLLM::Tool
  description "article slug가 실제로 존재하는지 확인한다. summary_body에 /articles/:slug 링크를 삽입하기 전에 검증용으로 사용한다."

  parameters type: "object",
    properties: {
      slug: {
        type: "string",
        description: "검증할 article slug"
      }
    },
    required: [ "slug" ]

  def execute(slug:)
    return { error: "slug가 필요합니다" } if slug.blank?

    if Article.kept.confirmed.exists?(slug: slug)
      { exists: true, path: "/articles/#{slug}" }
    else
      { exists: false, path: nil }
    end
  rescue StandardError => e
    { error: e.message }
  end
end
