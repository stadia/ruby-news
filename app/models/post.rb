# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

class Post < ApplicationRecord
  # ── Constants ────────────────────────────────────────────────────────
  MAX_BODY_LENGTH = 1000

  # ── Extend ───────────────────────────────────────────────────────────
  extend FriendlyId
  # 블로그 글은 발행 순간 제목에서 slug를 만들고(#1012), 나머지는 무작위 slug를 쓴다.
  # 숫자 slug는 friendly.find에서 같은 숫자의 다른 글 id를 가리므로 접미사를 붙인다.
  friendly_id :slug_candidates, use: :slugged,
                                slug_limit: BlogSlug::MAX_LENGTH,
                                treat_numeric_as_conflict: true,
                                treat_reserved_as_conflict: true

  # ── Includes ─────────────────────────────────────────────────────────
  include HtmlSanitizable
  include Posts::Blog
  include Posts::Federation
  include Posts::FederationIngest
  include Discard::Model
  include Fedipub::DataEntity
  include FedipubLikeable
  include FedipubBoostable

  self.discard_column = :deleted_at

  # ── Framework Macros ─────────────────────────────────────────────────
  acts_as_nested_set
  acts_as_taggable_on :tags

  # ── Enums ────────────────────────────────────────────────────────────
  enum :post_type, [ :short, :blog, :comment ], default: :short
  enum :status, [ :draft, :published ], default: :published

  # ── Associations ─────────────────────────────────────────────────────
  belongs_to :user, optional: true
  belongs_to :article, optional: true, counter_cache: :posts_count
  belongs_to :fedipub_actor, class_name: "Fedipub::Actor", optional: true

  # ── Scopes ───────────────────────────────────────────────────────────
  scope :comments, -> { where(post_type: :comment) }
  scope :standalone, -> { where(article_id: nil) }
  scope :visible, -> { where(status: :published).kept }
  scope :published_blog, -> { blog.published }

  # ── Validations ──────────────────────────────────────────────────────
  validates :body, presence: true, unless: :draft_blog?
  validates :title, presence: true, if: :published_blog?
  validates :slug, uniqueness: true, allow_nil: true
  validate :validate_user_or_actor
  validate :validate_parent_post

  # Fedipub::DataEntity가 추가하는 fedipub_actor presence 검증을 제거
  fedipub_actor_presence_validator = _validate_callbacks
    .map(&:filter)
    .find do |filter|
      filter.is_a?(ActiveRecord::Validations::PresenceValidator) &&
        filter.attributes == [ :fedipub_actor ]
    end
  skip_callback :validate, :before, fedipub_actor_presence_validator if fedipub_actor_presence_validator

  # ── Callbacks ────────────────────────────────────────────────────────
  before_validation :type_article_post_as_comment, on: :create
  after_validation :restore_slug_if_invalid
  after_commit :enqueue_reply_notification, on: :create
  after_commit :enqueue_article_thumbnail, on: :create

  # ── Soft delete ──────────────────────────────────────────────────────
  # Only published posts were ever federated, so only they emit Delete/Undo.
  # Drafts are local-only, so discarding/restoring one federates nothing.
  after_discard :handle_after_discard
  after_undiscard :handle_after_undiscard

  # ── Federation ───────────────────────────────────────────────────────
  acts_as_fedipub_data handles: "Note",
                         actor_entity_method: :federation_actor_entity,
                         soft_deleted_method: :discarded?,
                         soft_delete_date_method: :deleted_at,
                         should_federate_method: :should_federate?

  # Only blog posts support soft delete (trash/restore). Short posts and
  # comments hard-destroy, both locally and on inbound federated Delete, so
  # their rows (and counter caches) are removed as before.
  on_fedipub_delete_requested :handle_fedipub_delete_requested
  on_fedipub_undelete_requested :undiscard!

  # ── Public Instance Methods ──────────────────────────────────────────

  #: () -> (User | Fedipub::Actor)?
  def federation_actor_entity
    user || fedipub_actor
  end

  #: () -> bool
  def should_federate?
    # Only published posts federate. Drafts must stay local — without the
    # published? gate, Fedipub' after_create/after_update would push an
    # unpublished draft (and every autosave) to remote followers. Discarded
    # posts keep status :published, so after_discard can still emit a Delete.
    federation_actor_entity.present? && published?
  end


  #: () -> Integer
  def likes_count
    likers_count.to_i
  end

  #: () -> Integer
  def boosts_count
    boosters_count.to_i
  end

  #: () -> (Post | Article)
  def reply
    parent_local = parent
    return parent_local if parent_local

    article or raise "Post에 parent도 article도 없습니다"
  end

  #: () -> Array[String]
  def federation_reply_recipients
    actor = parent&.fedipub_actor
    if actor&.distant?
      [ actor.federated_url ]
    else
      []
    end
  end

  #: () -> String
  def author_name
    user&.full_name || fedipub_actor&.username || "익명"
  end

  #: () -> String?
  def author_host
    return if user_id.present?
    return if fedipub_actor.nil? || fedipub_actor&.server.blank?
    "(#{fedipub_actor&.server})"
  end

  # FriendlyId::Candidates가 호출하므로 public이다.
  # 후보는 slug_candidates에서 이미 정규화했다. 기본 parameterize는 한글을 지운다.
  #: (untyped value) -> String
  def normalize_friendly_id(value)
    publishing_blog? ? value.to_s : super
  end

  # ── Private Instance Methods ─────────────────────────────────────────
  private

  #: () -> void
  def handle_after_discard
    create_fedipub_activity "Delete" if published?
  end

  #: () -> void
  def handle_after_undiscard
    create_fedipub_activity "Undo" if published?
  end

  #: () -> void
  def handle_fedipub_delete_requested
    logger.info { "Federated post deletion requested #{id}" }
    blog? ? discard! : destroy!
  end

  def create_fedipub_activity(action, actor: nil, to: nil, cc: nil)
    actor ||= fedipub_actor || user&.fedipub_actor
    return if actor.blank?

    # A draft never federated, so its first publish fires an "Update" (via the
    # after_update callback) that remotes would drop — there's no object to
    # update yet. Promote that first Update to a "Create" so the post is
    # actually delivered. Once a Create exists, later edits federate as Updates.
    if action == "Update" && !Fedipub::Activity.exists?(entity: self, action: "Create")
      action = "Create"
    end

    super(action, actor: actor, to: to, cc: cc)
  end

  # Posts attached to an article are comments and must stay in the `comments`
  # scope (post_type = :comment). The enum default is :short, so any creation
  # path that doesn't explicitly type the post (e.g. the local comment UI) would
  # otherwise leave an article-attached post as :short and drop it from the
  # comments list. We only promote the default :short here, so an explicitly
  # typed :longform or already :comment (e.g. federated reply_attributes) is
  # left untouched. Standalone posts (article_id nil) are never affected.
  #: () -> void
  def type_article_post_as_comment
    self.post_type = :comment if article_id.present? && short?
  end

  #: () -> void
  def enqueue_reply_notification
    unless parent_id.present?
      logger.debug { "ReplyNotification skip: post #{id} has no parent" }
      return
    end
    unless parent&.user_id.present?
      logger.debug { "ReplyNotification skip: parent post #{parent_id} has no local user" }
      return
    end
    local_parent = parent
    unless local_parent
      # Unreachable: the guard above already returns when `parent` is nil.
      # Logged anyway so this exit matches its siblings -- a silent return
      # here would blank out the debug trail exactly where you would look.
      logger.debug { "ReplyNotification skip: parent #{parent_id} disappeared between checks" }
      return
    end

    if local_parent.user_id == user_id
      logger.debug { "ReplyNotification skip: self-reply by user #{user_id}" }
      return
    end

    logger.info { "ReplyNotification enqueue: post #{id} → parent #{parent_id} (user #{local_parent.user_id})" }
    ReplyNotificationJob.perform_later(local_parent.id, id)
  end

  #: () -> void
  def enqueue_article_thumbnail
    article_id_local = article_id
    return unless article_id_local.present?
    article_local = article
    return if article_local.nil? || article_local.thumbnail.attached?

    logger.info { "ArticleThumbnail enqueue: comment on article #{article_id_local}" }
    ArticleThumbnailJob.perform_later(article_id_local)
  end

  #: () -> void
  def set_fedipub_actor
    return if federation_actor_entity.nil?

    super
  end

  #: () -> void
  def validate_user_or_actor
    unless user_id.present? || fedipub_actor_id.present?
      errors.add(:base, "user 또는 fedipub_actor가 필요합니다")
    end
  end

  #: () -> void
  def validate_parent_post
    return unless parent_id.present?

    if parent.nil?
      errors.add(:parent_id, "원본 포스트를 찾을 수 없습니다.")
    end
  end

  # 발행된 글의 slug는 제목을 바꿔도 유지한다. 공유된 링크가 예고 없이 깨지지 않도록
  # 발행 취소 기능이 없으므로 초안의 임시 slug만 최초 발행 순간 교체한다.
  def should_generate_new_friendly_id?
    slug.blank? || (publishing_blog? && !slug_changed?)
  end

  #: () -> bool
  def publishing_blog?
    published_blog? && (new_record? || status_changed?)
  end

  #: () -> Array[String]
  def slug_candidates
    return [ random_slug ] unless publishing_blog?

    base = BlogSlug.normalize(title)
    return [ random_slug ] if base.empty?

    [ base, BlogSlug.with_suffix(base) ]
  end

  # 발행 검증이 실패하면 set_slug가 바꿔 둔 slug를 저장된 값으로 되돌린다. 그대로 두면
  # 다시 그린 편집 화면의 폼이 저장되지 않은 slug로 향해 404가 난다. 새 글은 저장된
  # 값이 없으므로 nil로 비워, 제목을 고쳐 다시 저장할 때 slug를 새로 만들게 한다.
  # FriendlyId는 slug 자체의 오류만 복원하므로 본문·제목 오류도 여기서 복원한다.
  #: () -> void
  def restore_slug_if_invalid
    return if errors.empty? || !slug_changed?

    self.slug = slug_in_database
  end

  #: () -> String
  def random_slug
    SecureRandom.urlsafe_base64(16).downcase
  end
end
