# frozen_string_literal: true

require "test_helper"

class PushSubscriptionTest < ActiveSupport::TestCase
  setup do
    @user = users(:john)
  end

  test "유효한 속성이면 저장된다" do
    subscription = PushSubscription.new(
      user: @user,
      endpoint: "https://fcm.googleapis.com/fcm/send/new-subscription-123",
      p256dh: "test_p256dh",
      auth: "test_auth"
    )

    assert_predicate subscription, :valid?
  end

  test "신뢰할 수 없는 endpoint는 유효하지 않다" do
    subscription = PushSubscription.new(
      user: @user,
      endpoint: "https://malicious.example.com/subscription",
      p256dh: "test_p256dh",
      auth: "test_auth"
    )

    assert_not subscription.valid?
    assert_includes subscription.errors[:endpoint], "is not a valid push service endpoint"
  end

  test "endpoint가 없으면 유효하지 않다" do
    subscription = PushSubscription.new(user: @user, p256dh: "key", auth: "auth")

    assert_not subscription.valid?
    assert_includes subscription.errors[:endpoint], "내용을 입력해 주세요"
  end

  test "endpoint는 고유해야 한다" do
    existing = push_subscriptions(:john_browser)

    duplicate = PushSubscription.new(
      user: users(:jane),
      endpoint: existing.endpoint,
      p256dh: "another",
      auth: "another"
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:endpoint], "이미 존재하는 값입니다"
  end

  test "Apple 호스트처럼 보이지만 실제 호스트가 다른 endpoint는 유효하지 않다" do
    [
      "https://192.168.1.150:8443?x.push.apple.com/a",
      "https://evil.example#.push.apple.com/a",
      "https://evil.example@web.push.apple.com/a"
    ].each do |endpoint|
      subscription = PushSubscription.new(user: @user, endpoint:, p256dh: "key", auth: "auth")

      assert_not subscription.valid?, endpoint
    end
  end

  test "정상 푸시 서비스 endpoint는 유효하다" do
    [
      "https://fcm.googleapis.com/fcm/send/abc",
      "https://updates.push.services.mozilla.com/wpush/v2/abc",
      "https://web.push.apple.com/QAbc"
    ].each do |endpoint|
      subscription = PushSubscription.new(user: @user, endpoint:, p256dh: "key", auth: "auth")

      assert_predicate subscription, :valid?, endpoint
    end
  end
end
