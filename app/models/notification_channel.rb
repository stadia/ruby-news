# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

class NotificationChannel < ApplicationRecord
  # reason은 거절 사유(:discarded, :channel_changed)다. 운영 로그에서 삭제된
  # 채널의 복구 시도와 다른 채널로의 교체 시도를 구분하는 데 쓴다.
  # 메시지에는 식별자만 담고 webhook URL(토큰)은 담지 않는다.
  class RelinkRejected < StandardError
    #: () -> Symbol
    def reason = @reason

    #: (Symbol reason, ?remote_id: String?, ?existing_channel_id: String?, ?incoming_channel_id: String?) -> void
    def initialize(reason, remote_id: nil, existing_channel_id: nil, incoming_channel_id: nil)
      @reason = reason
      super("relink rejected reason=#{reason} remote_id=#{remote_id} " \
            "existing_channel_id=#{existing_channel_id} incoming_channel_id=#{incoming_channel_id}")
    end
  end

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

    reason = if discarded? then :discarded
    elsif channel_id != incoming_channel_id then :channel_changed
    end
    return unless reason

    raise RelinkRejected.new(reason, remote_id:, existing_channel_id: channel_id, incoming_channel_id:)
  end

  scope :active, -> { kept.where(status: :active) }
  scope :delivery_ready, -> {
    active.where.not(webhook_url: [ nil, "" ]).where.not(channel_id: [ nil, "" ]).where.not(channel_name: [ nil, "" ])
  }
end
