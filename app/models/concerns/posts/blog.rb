# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

# Blog-specific behavior for Post: publishing, draft/published predicates,
# summary generation, and draft content validation.
#
# The post_type/status enums and blog scopes remain on Post itself,
# since they are referenced as class methods elsewhere.
module Posts
  module Blog
    extend ActiveSupport::Concern

    BLOG_SUMMARY_LENGTH = 280

    included do
      validate :validate_blog_draft_content
    end

    #: () -> void
    def publish!
      self.published_at ||= Time.current
      self.status = :published
      save!
    end

    #: () -> bool
    def draft_blog?
      blog? && draft?
    end

    #: () -> bool
    def published_blog?
      blog? && published?
    end

    #: () -> String
    def blog_summary
      stripped = Rails::Html::FullSanitizer.new.sanitize(body.to_s).squish
      stripped.truncate(BLOG_SUMMARY_LENGTH)
    end

    private

    # HtmlSanitizable#sanitize_body(before_save)를 장문에 한해 BlogBody 규칙으로 바꾼다.
    # Post가 HtmlSanitizable 다음에 이 모듈을 include하므로 이 정의가 먼저 잡힌다.
    #: () -> void
    def sanitize_body
      return super unless blog?

      self.body = BlogBody.sanitize(body)
    end

    #: () -> void
    def validate_blog_draft_content
      return unless draft_blog?
      return if title.present? || body.present?

      errors.add(:base, I18n.t("posts.blog.errors.blank_draft"))
    end
  end
end
