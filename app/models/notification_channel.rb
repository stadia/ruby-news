# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

class NotificationChannel < ApplicationRecord
  class RelinkRejected < StandardError; end

  include Discard::Model
  self.discard_column = :deleted_at

  has_many :notification_deliveries, dependent: :restrict_with_error

  enum :status, {
    active: "active",
    inactive: "inactive",
    error: "error"
  }, default: :active, validate: true

  validates :remote_id, :name, :webhook_url, :channel_id, :channel_name, presence: true
  validates :remote_id, uniqueness: { scope: :type }

  # 호출자는 저장 트랜잭션 안에서 기존 레코드 잠금을 획득해야 한다.
  #: (String incoming_channel_id) -> void
  def ensure_relink_allowed!(incoming_channel_id)
    return if new_record?
    return if !discarded? && channel_id == incoming_channel_id

    raise RelinkRejected, "Existing notification channel cannot be replaced"
  end

  scope :active, -> { kept.where(status: :active) }
  scope :delivery_ready, -> {
    active.where.not(webhook_url: [ nil, "" ]).where.not(channel_id: [ nil, "" ]).where.not(channel_name: [ nil, "" ])
  }
end
