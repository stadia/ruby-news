# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

class Article < ApplicationRecord
  # ── Constants ────────────────────────────────────────────────────────
  TITLE_MAX_LENGTH = 200
  TITLE_OMISSION = "..."
  TITLE_BOUNDARY_MIN_RATIO = 0.6
  TITLE_BOUNDARY_PATTERN = /[\s[:punct:]、。，．！？；：·|｜-]/

  # title 이 일본어인지 판별한다. 가나(かな) 또는 한자(漢字) 포함 여부로 본다.
  # 한국어 제목에는 한자가 들어가지 않는다는 전제이며, 검색용 판별인
  # JAPANESE_KANA_REGEX 와 달리 한자까지 일본어로 취급한다.
  JAPANESE_TITLE_REGEX = /[\p{Hiragana}\p{Katakana}\p{Han}･-ﾟ]/

  # ── Extend ───────────────────────────────────────────────────────────
  extend FriendlyId
  friendly_id :slug, use: :slugged

  # ── Includes ─────────────────────────────────────────────────────────
  include PgSearch::Model
  include Discard::Model
  include Fedipub::DataEntity
  include FedipubLikeable
  include FedipubBoostable
  include Articles::LocalizedDisplay
  include Articles::Activitypub

  # ── Framework macros ─────────────────────────────────────────────────
  self.discard_column = :deleted_at
  acts_as_taggable_on :tags

  # SQLite는 벡터 임베딩을 지원하지 않으므로 PostgreSQL에서만 활성화
  # PostgreSQL은 컬럼 타입(halfvec)을 자동 감지하므로 type: 지정 불필요(SQLite 전용 옵션)
  has_neighbors :embedding, dimensions: 3072

  multisearchable against: [
    :title, :title_ko, :title_ja,
    :summary_key, :summary_key_ja,
    :summary_detail, :summary_detail_ja,
    :body, :summary_body, :summary_body_ja
  ],
                   if: ->(record) { record.deleted_at.nil? }

  store_accessor :summary_detail, :introduction, :conclusion, prefix: :summary
  store_accessor :summary_detail_ja, :introduction, :conclusion, prefix: :summary_ja
  store_accessor :social_post_ids, :twitter_id, :mastodon_id

  # ── Associations ─────────────────────────────────────────────────────
  belongs_to :user
  belongs_to :site, optional: true
  belongs_to :fedipub_actor, class_name: "Fedipub::Actor", optional: true

  has_many :posts, dependent: :nullify
  has_many :notification_deliveries, dependent: :destroy

  # 명명된 변형: 렌더 시 직접 CDN URL(cdn.ruby-news.dev)을 쓰기 위해 미리 처리해 둔다.
  # (기존 인라인 변형과 동일한 resize_to_fill 이라 digest/key가 같아 재사용된다.)
  #   :hero → 히어로/기사 상세, :card → 작은 카드 및 히어로 모바일 srcset
  THUMBNAIL_VARIANTS = { hero: [ 1200, 675 ], card: [ 600, 338 ] }.freeze

  has_one_attached :thumbnail do |attachable|
    THUMBNAIL_VARIANTS.each do |name, dimensions|
      attachable.variant name, resize_to_fill: dimensions
    end
  end

  # ── Scopes ───────────────────────────────────────────────────────────
  # 하이브리드 전문 검색:
  #   1) tsvector_content_tsearch(textsearch_ko, 'korean') — 한국어 형태소 + 한자
  #   2) content LIKE(pg_bigm) — 한국어 사전이 못 잡는 일본어 가나(かな) 폴백
  #
  # LIKE 분기는 content 컬럼 detoast + bigm 인덱스 recheck 비용이 커서
  # (production 측정 시 150~250ms) term 에 가나가 포함된 경우에만 활성화한다.
  # 영/한 term 은 tsvector 분기만 타서 ts_rank GIN 으로 빠르게 종결.
  # LIKE 는 gin_bigm_ops 인덱스를 타지만 ILIKE 는 타지 않으므로 LIKE 를 사용한다.
  JAPANESE_KANA_REGEX = /[\p{Hiragana}\p{Katakana}･-ﾟ]/

  scope :full_text_search_for, ->(term) do
    term = term.to_s.strip
    next none if term.blank?

    tsquery = "websearch_to_tsquery('korean', #{connection.quote(term)})"
    where_clause =
      if term.match?(JAPANESE_KANA_REGEX)
        like = connection.quote("%#{sanitize_sql_like(term)}%")
        "pg_search_documents.tsvector_content_tsearch @@ #{tsquery} " \
          "OR pg_search_documents.content LIKE #{like}"
      else
        "pg_search_documents.tsvector_content_tsearch @@ #{tsquery}"
      end

    joins(:pg_search_document)
      .where(where_clause)
      .order(Arel.sql("ts_rank(pg_search_documents.tsvector_content_tsearch, #{tsquery}) DESC"), created_at: :desc)
  end
  scope :related, -> { kept.where(is_related: true) }
  scope :unrelated, -> { kept.where(is_related: false) }
  scope :confirmed, -> { where("slug IS NOT NULL AND title_ko IS NOT NULL") }

  # TOAST 컬럼(body, summary_body, embedding) 제외 스코프
  scope :without_toast, -> {
    select(column_names - %w[body summary_body embedding])
  }

  # ── 일본어 번역 결손 탐지 ─────────────────────────────────────────────
  # summary_body_ja 안의 한글 비율. 고유명사·인용 병기 정도는 이 값 아래에 머무르고,
  # 번역이 중간에 끊긴 글만 이 값을 넘는다.
  JA_HANGUL_RATIO_THRESHOLD = 0.08
  JA_HANGUL_RATIO_SQL = <<~SQL.squish
    length(regexp_replace(summary_body_ja, '[^가-힣]', '', 'g'))::numeric
      / nullif(length(summary_body_ja), 0)
  SQL

  # 한국어 요약은 있는데 일본어 요약이 비어 있는 아티클
  scope :missing_japanese, -> {
    kept.where("summary_body_ja IS NULL OR btrim(summary_body_ja) = ''")
        .where("summary_body IS NOT NULL AND btrim(summary_body) <> ''")
  }

  # 일본어 요약에 한글이 임계값 넘게 남아 있는(=번역이 덜 된) 아티클
  scope :hangul_leftover_japanese, ->(threshold = JA_HANGUL_RATIO_THRESHOLD) {
    kept.where("summary_body_ja ~ '[가-힣]'")
        .where("#{JA_HANGUL_RATIO_SQL} > ?", threshold)
  }

  # 일본어 재번역이 필요한 아티클 전체
  scope :needs_japanese, -> { missing_japanese.or(hangul_leftover_japanese) }

  # ID + 필수 컬럼만 선택 (Admin용)
  scope :for_admin_index, -> {
    select(:id, :title_ko, :slug, :host, :is_related, :published_at, :created_at, :updated_at)
  }

  pg_search_scope :title_matching, against: [ :title, :title_ko ], using: { tsearch: { dictionary: "korean" } }
  pg_search_scope :body_matching, against: [ :body, :summary_body ], using: { tsearch: { dictionary: "korean" } }

  # ── Validations ──────────────────────────────────────────────────────
  validates :title, length: { maximum: TITLE_MAX_LENGTH }, allow_blank: true
  validates :url, :origin_url, presence: true, uniqueness: { case_sensitive: false }
  validates :slug, uniqueness: true, allow_blank: true

  # ── Callbacks ────────────────────────────────────────────────────────
  before_validation on: :create do
    url_local = url
    self.origin_url = url_local if url_local && origin_url.blank?
  end

  before_create :generate_metadata

  before_save do
    # 제목에 "Show HN"이 포함되어 있으면 discard 처리
    if title&.match?(/Show HN/i)
      self.deleted_at = Time.zone.now
    end
  end

  # title 이 일본어(가나 또는 한자 포함)인 경우 title_ja 에도 함께 저장한다.
  # 판별 기준은 JAPANESE_TITLE_REGEX 를 사용한다.
  before_save :assign_japanese_title

  after_commit :clear_rss_cache, on: [ :create, :update, :destroy ]
  after_commit :enqueue_index_now, on: [ :create, :update ]

  after_discard :handle_after_discard
  after_undiscard :handle_after_undiscard

  # ── Federation ───────────────────────────────────────────────────────
  acts_as_fedipub_data handles: "Note",
                         actor_entity_method: :bot_user,
                         soft_deleted_method: :discarded?,
                         soft_delete_date_method: :deleted_at,
                         should_federate_method: :should_federate?

  on_fedipub_delete_requested :handle_fedipub_delete_requested
  on_fedipub_undelete_requested :undiscard!

  # ── Public Instance Methods ──────────────────────────────────────────

  #: () -> String
  def to_markdown
    Articles::Markdown.render(self)
  end

  #: () -> void
  def generate_metadata
    result = metadata_service.call(self)
    logger.debug { "Article metadata preparation failed for #{url}: #{result.failure}" } if result.failure?
    return unless result.failure? && result.failure == :blocked_url

    errors.add(:url, :invalid)
    throw :abort
  end

  #: (untyped value) -> void
  def title=(value)
    super(Articles::Utils.truncate_title(value))
  end

  #: () -> String?
  def youtube_id
    # nil 체크를 포함하여 안전하게 접근
    url_local = url
    if url_local.is_a?(String)
      uri = URI.parse(url_local)
      query = uri.query
      if query.present?
        URI.decode_www_form(query).to_h["v"]
      elsif (path = uri.path) && path.start_with?("/live")
        path.split("/").last
      end
    end
  rescue URI::InvalidURIError
    logger.error "Invalid URI for youtube_id: #{url}"
    nil
  end

  #: () -> bool
  def update_slug
    if is_youtube?
      new_slug = youtube_id
    else
      url_local = url
      if url_local.blank?
        logger.error "update_slug: article #{id}에 url이 없어 slug를 만들 수 없습니다"
        return false
      end

      path = URI.parse(url_local).path
      new_slug = path&.split("/")&.last&.split(".")&.first
      new_slug = random_slug if new_slug.blank?
    end
    update(slug: new_slug)
  rescue URI::InvalidURIError
    logger.error "Invalid URI for slug update: #{url}"
    false
  end

  #: () -> String?
  def user_name
    if (local_site = site)
      local_site.name
    else
      host
    end
  end

  #: () -> { title: String?, summary: String }
  def base_content
    title = title_ko.presence || self.title
    summary = summary_key&.first.presence || I18n.t("articles.default_summary")
    { title:, summary: }
  end

  #: () -> bool
  def should_federate?
    return false if user.blank?

    title_ko.present?
  end

  # 기사의 ActivityPub actor 는 항상 발행 봇 user 의 actor 다.
  # fedipub_actor_id 컬럼은 과거에 비워진 채 생성된 기사가 많아
  # (create_fedipub_activity 와 동일하게) 봇 actor 로 폴백한다.
  # fedipub published 엔드포인트의 직렬화(Note.to_federation / PublishableResource)가
  # fedipub_actor 를 직접 참조하므로 nil 이면 500 이 발생한다.
  #: () -> Fedipub::Actor?
  def fedipub_actor
    super || bot_user&.fedipub_actor
  end

  #: () -> Integer
  def likes_count
    likers_count.to_i
  end

  #: () -> Integer
  def boosts_count
    boosters_count.to_i
  end

  # slug로 Article을 찾는 메서드
  #: (String slug) -> Article?
  def self.find_by_slug(slug)
    find_by(slug: slug)
  end

  # ── Private Instance Methods ─────────────────────────────────────────
  private

  #: () -> void
  def handle_after_discard
    clear_rss_cache
    SocialDeleteJob.perform_later(id)
    create_fedipub_activity "Delete"
  end

  #: () -> void
  def handle_after_undiscard
    create_fedipub_activity "Undo"
  end

  #: () -> void
  def handle_fedipub_delete_requested
    logger.info { "Federated article deletion requested #{id}" }
    discard!
  end

  #: () -> void
  def assign_japanese_title
    title_local = title
    return if title_local.nil? || title_local.blank?
    return unless title_local.match?(JAPANESE_TITLE_REGEX)

    self.title_ja = title_local
  end

  #: () -> User?
  def bot_user
    User.first_bot
  end

  #: (String action, ?actor: (Fedipub::Actor)?, ?to: untyped, ?cc: untyped) -> void
  def create_fedipub_activity(action, actor: nil, to: nil, cc: nil)
    actor ||= fedipub_actor || bot_user&.fedipub_actor
    return if actor.blank?

    if action == "Update"
      if Fedipub::Activity.exists?(entity: self, action: "Create")
        logger.info do
          {
            message: "[Federation] Skipping repeated Article update activity",
            article_id: id,
            federated_url: federated_url
          }.inspect
        end
        return
      end
      action = "Create"
    end

    super(action, actor: actor, to: to, cc: cc)
  end

  # HomeController#rss 가 읽고 이 콜백이 지운다. 캐시에는 반드시 로드된 레코드가
  # 들어가야 한다 - 지연 평가 Relation 을 넣으면 컬럼 목록이 문자열로 굳어져
  # 스키마 변경 이후 재생될 때 깨진다(아래 v2 주석 참고).
  # v2: federails_actor_id -> fedipub_actor_id 리네임 시점에 v1 항목이 옛 컬럼
  # 목록을 들고 있어 PG::UndefinedColumn 을 냈다. 키를 올려 오염된 항목을 버린다.
  RSS_CACHE_KEY = "rss_articles/v2"

  #: () -> void
  def clear_rss_cache
    Rails.cache.delete(RSS_CACHE_KEY)
  end

  INDEX_NOW_WATCHED_ATTRIBUTES = %w[slug title title_ko title_ja body summary_body summary_body_ja published_at].freeze

  #: () -> void
  def enqueue_index_now
    return unless kept?
    return if slug.blank? || title_ko.blank?
    return unless INDEX_NOW_WATCHED_ATTRIBUTES.any? { |attr| saved_change_to_attribute?(attr) }

    # 호스트별 ping은 IndexNowJob이 담당한다(IndexNow는 host 1개 = POST 1개).
    # 여기선 기사당 잡 1개만 예약하고 per-article 잠금으로 60s 디바운스한다.
    lock_key = "index_now:enqueue:#{id}"
    return unless Rails.cache.write(lock_key, true, expires_in: 60.seconds, unless_exist: true)

    IndexNowJob.set(wait: 30.seconds).perform_later(id)
  end

  #: () -> bool
  def should_generate_new_friendly_id?
    false
  end

  #: () -> String
  def random_slug
    "#{Time.zone.now.strftime('%Y%m%d')}-#{SecureRandom.hex(4)}"
  end

  #: () -> Articles::MetadataPreparationService
  def metadata_service
    @metadata_service ||= Articles::MetadataPreparationService.new
  end
end
