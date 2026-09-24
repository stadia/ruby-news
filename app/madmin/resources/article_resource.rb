# typed: true

class ArticleResource < Madmin::Resource
  # Attributes
  attribute :id, form: false
  attribute :title, new: false
  attribute :title_ko, index: true, new: false
  attribute :title_ja, index: false, form: false
  attribute :slug, index: false, form: false
  attribute :deleted_at, index: false, form: false
  attribute :discarded?, index: true, form: false
  attribute :host, index: true, form: false
  attribute :is_related, index: true, new: false
  attribute :created_at, index: false, form: false

  attribute :url, index: false
  attribute :updated_at, form: false
  attribute :published_at, new: false
  attribute :origin_url, index: false, new: false
  attribute :tag_list, index: false, new: false
  attribute :is_youtube, index: false, new: false
  attribute :body, index: false, form: true, field: LexxyEditorField
  attribute :is_posted, index: false, form: true

  attribute :summary_key, index: false, form: false
  attribute :summary_key_ja, index: false, form: false
  attribute :summary_detail, index: false, form: false
  attribute :summary_introduction, index: false
  attribute :summary_body, index: false
  attribute :summary_conclusion, index: false

  # attribute :twitter_id, index: false, form: false
  attribute :mastodon_id, index: false, form: false

  # ActiveStorage
  attribute :thumbnail, index: false, form: false

  # Associations
  attribute :user, index: false, form: false
  attribute :site, index: true, form: false

  # Add scopes to easily filter records
  scope :kept
  scope :discarded
  scope :related
  scope :unrelated

  # Add actions to the resource's show page
  member_action do |record|
    actions = []

    if record.is_a?(Article) && record.deleted_at.nil?
      actions << button_to("Discard", discard_madmin_article_path(record), method: :put, data: { turbo_confirm: "이 기사를 폐기하시겠습니까?" },
        class: "btn btn-danger bg-red-600 text-white rounded px-4 py-2 hover:bg-red-700")
    else
      actions << button_to("Restore", restore_madmin_article_path(record), method: :put, data: { turbo_confirm: "이 기사를 복원하시겠습니까?" },
        class: "btn btn-success bg-green-600 text-white rounded px-4 py-2 hover:bg-green-700")
    end

    if record.is_a?(Article) && record.is_related?
      actions << button_to("Mark Unrelated", mark_unrelated_madmin_article_path(record), method: :put, data: { turbo_confirm: "이 기사를 관련 없음으로 표시하시겠습니까?" },
        class: "btn btn-warning bg-yellow-600 text-white rounded px-4 py-2 hover:bg-yellow-700")
    end

    actions << button_to("재처리", reprocess_madmin_article_path(record), method: :put, data: { turbo_confirm: "이 기사의 AI 요약을 다시 생성하시겠습니까?" },
      class: "btn btn-primary bg-blue-600 text-white rounded px-4 py-2 hover:bg-blue-700")

    actions << button_to("썸네일 재생성", regenerate_thumbnail_madmin_article_path(record), method: :put, data: { turbo_confirm: "이 기사의 썸네일을 삭제하고 다시 생성하시겠습니까?" },
      class: "btn btn-primary bg-indigo-600 text-white rounded px-4 py-2 hover:bg-indigo-700")

    actions << button_to("일본어 재번역", translate_japanese_madmin_article_path(record), method: :put, data: { turbo_confirm: "이 기사의 일본어 번역을 다시 생성하시겠습니까?" },
      class: "btn btn-primary bg-teal-600 text-white rounded px-4 py-2 hover:bg-teal-700")

    safe_join(actions, " ")
  end

  # Customize the display name of records in the admin area.
  # def self.display_name(record) = record.name

  # Customize the default sort column and direction.
  # def self.default_sort_column = "created_at"
  #
  # def self.default_sort_direction = "desc"
end
