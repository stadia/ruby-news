# typed: true

class SiteResource < Madmin::Resource
  # Attributes
  attribute :id, form: false
  attribute :name
  attribute :url, index: true
  attribute :base_uri, form: false, index: true
  attribute :email, index: true
  attribute :path, form: false
  attribute :channel, index: true
  attribute :last_checked_at, index: true, form: false

  attribute :client
  attribute :created_at, form: false, index: false
  attribute :updated_at, form: false
  attribute :deleted_at, index: true, form: false

  # Associations
  attribute :articles, form: false

  # Add scopes to easily filter records
  scope :kept
  scope :discarded

  # Add actions to the resource's show page
  member_action do |record|
    if record.is_a?(Site) && record.deleted_at.nil?
      button_to "폐기", discard_madmin_site_path(record), method: :put, data: { turbo_confirm: "정말 이 사이트를 폐기하시겠습니까?" },
    class: "btn btn-danger"
    else
      button_to "복원", restore_madmin_site_path(record), method: :put, data: { turbo_confirm: "정말 이 사이트를 복원하시겠습니까?" },
    class: "btn btn-secondary"
    end
  end

  # Customize the display name of records in the admin area.
  # def self.display_name(record) = record.name

  # Customize the default sort column and direction.
  # def self.default_sort_column = "created_at"
  #
  # def self.default_sort_direction = "desc"
end
