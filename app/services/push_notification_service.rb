# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

class PushNotificationService < OperationService
  #: (user: User, title: String, body: String, path: String) -> Dry::Monads::Result
  def call(user:, title:, body:, path:)
    step validate_push_configured(user:, title:, body:, path:)

    payload = build_payload(title: title, body: body, path: path)
    step deliver_to_subscriptions(user:, payload:)
  end

  #: (user: User, title: String, body: String, path: String) -> Dry::Monads::Result
  def notify_user(user:, title:, body:, path:)
    call(user:, title:, body:, path:)
  end

  protected

  # Dry::Operation의 call에서 return Failure(...)를 직접 반환하면 Success(Failure(...))로 감싸지므로
  # guard clause는 반드시 step으로 호출되는 별도 메서드에 위치시킨다.
  #: (user: User, title: String, body: String, path: String) -> Dry::Monads::Result
  def validate_push_configured(user:, title:, body:, path:)
    unless Configs::WebPush.configured?
      logger.warn "PushNotificationService: VAPID keys not configured"
      return Failure(:web_push_not_configured)
    end
    Success(user:, title:, body:, path:)
  end

  private

  #: (user: User, payload: String) -> Dry::Monads::Result
  def deliver_to_subscriptions(user:, payload:)
    subscriptions = user.push_subscriptions.to_a

    if subscriptions.empty?
      logger.info "PushNotificationService: user #{user.id} has no push subscriptions"
      return Failure(:no_subscriptions)
    end

    logger.info "PushNotificationService: delivering to #{subscriptions.size} subscription(s) for user #{user.id}"

    subscriptions.each do |subscription|
      send_single(subscription:, payload:)
    end

    Success(true)
  end

  #: (title: String, body: String, path: String) -> String
  def build_payload(title:, body:, path:)
    {
      title: title,
      options: {
        body: body,
        icon: "/icon.png",
        badge: "/icon.png",
        data: { path: path }
      }
    }.to_json
  end

  #: (subscription: PushSubscription, payload: String) -> void
  def send_single(subscription:, payload:)
    # 허용 목록이 좁아지기 전에 저장된 구독은 검증을 거치지 않았으므로 발송 직전에 다시 확인한다.
    unless subscription.endpoint.match?(PushSubscription::TRUSTED_PUSH_SERVICES)
      logger.warn "PushNotificationService: subscription #{subscription.id} endpoint not trusted, destroying"
      return subscription.destroy!
    end

    WebPush.payload_send(
      message: payload,
      endpoint: subscription.endpoint,
      p256dh: subscription.p256dh,
      auth: subscription.auth,
      vapid: {
        subject: Configs::WebPush.subject,
        public_key: Configs::WebPush.public_key,
        private_key: Configs::WebPush.private_key,
        expiration: Configs::WebPush.expiration_seconds
      }
    )

    subscription.update_columns(last_sent_at: Time.current, last_error_at: nil)
    logger.info "PushNotificationService: sent to subscription #{subscription.id} (endpoint: #{subscription.endpoint.truncate(60)})"
  rescue WebPush::ExpiredSubscription, WebPush::InvalidSubscription => e
    logger.info "PushNotificationService: subscription #{subscription.id} expired/invalid (#{e.class}), destroying"
    subscription.destroy!
  rescue WebPush::Unauthorized => e
    if vapid_key_mismatch?(e)
      logger.warn "PushNotificationService: VAPID key mismatch for subscription #{subscription.id}, destroying"
      subscription.destroy!
    else
      subscription.update_columns(last_error_at: Time.current)
      logger.error "PushNotificationService: unauthorized for subscription #{subscription.id}: #{e.message}"
      raise
    end
  rescue WebPush::ResponseError => e
    if subscription_expired?(e)
      logger.info "PushNotificationService: subscription #{subscription.id} expired (HTTP #{e.response&.code}), destroying"
      subscription.destroy!
    else
      subscription.update_columns(last_error_at: Time.current)
      logger.error "PushNotificationService: response error for subscription #{subscription.id}: #{e.message}"
      raise
    end
  end

  #: (WebPush::ResponseError error) -> bool
  def subscription_expired?(error)
    status_code = error.response&.code.to_i
    status_code == 404 || status_code == 410
  end

  #: (WebPush::Unauthorized error) -> bool
  def vapid_key_mismatch?(error)
    status_code = error.response&.code.to_i
    response_body = error.response&.body.to_s

    status_code == 401 && response_body.include?("VAPID public key mismatch")
  end
end
