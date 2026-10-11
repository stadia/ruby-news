# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

class PushSubscription < ApplicationRecord
  belongs_to :user

  TRUSTED_PUSH_SERVICES = %r{\Ahttps://(fcm\.googleapis\.com|updates\.push\.services\.mozilla\.com|android\.googleapis\.com|[a-z0-9.-]+\.push\.apple\.com)/.*\z}

  validates :endpoint, presence: true, uniqueness: true,
                       format: { with: TRUSTED_PUSH_SERVICES, message: "is not a valid push service endpoint" }
  validates :p256dh, presence: true
  validates :auth, presence: true
end
