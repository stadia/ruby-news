# frozen_string_literal: true

require "test_helper"

class PushNotificationServiceTest < ActiveSupport::TestCase
  setup do
    @user = users(:john)
    @subscription = push_subscriptions(:john_browser)
    @service = PushNotificationService.new
  end

  test "설정이 존재하면 WebPush로 발송한다" do
    payload_sent = false
    push_stub = proc do |**kwargs|
      payload_sent = true

      assert_equal @subscription.endpoint, kwargs[:endpoint]
      assert_equal @subscription.p256dh, kwargs[:p256dh]
      assert_equal @subscription.auth, kwargs[:auth]
      expiration = kwargs.dig(:vapid, :expiration)

      assert_equal Configs::WebPush.expiration_seconds, expiration
      assert_operator expiration, :<=, Configs::WebPush::MAX_EXPIRATION_SECONDS
    end

    Configs::WebPush.stub(:configured?, true) do
      Configs::WebPush.stub(:subject, "mailto:admin@example.com") do
        Configs::WebPush.stub(:public_key, "public") do
          Configs::WebPush.stub(:private_key, "private") do
            WebPush.stub(:payload_send, push_stub) do
              @service.notify_user(user: @user, title: "title", body: "body", path: "/articles/test")
            end
          end
        end
      end
    end

    assert payload_sent
    assert_not_nil @subscription.reload.last_sent_at
  end

  test "설정이 없으면 발송하지 않는다" do
    assert_nothing_raised do
      Configs::WebPush.stub(:configured?, false) do
        WebPush.stub(:payload_send, ->(**_kwargs) { raise "should not be called" }) do
          @service.notify_user(user: @user, title: "title", body: "body", path: "/articles/test")
        end
      end
    end
  end

  # 허용 목록이 좁아지기 전에 저장된 구독은 발송하지 않고 삭제한다.
  test "허용 목록 밖 endpoint는 발송하지 않고 구독을 삭제한다" do
    @subscription.update_columns(endpoint: "https://evil.example/push")

    Configs::WebPush.stub(:configured?, true) do
      WebPush.stub(:payload_send, ->(**_kwargs) { flunk "허용 목록 밖으로 발송하면 안 된다" }) do
        @service.notify_user(user: @user, title: "title", body: "body", path: "/articles/test")
      end
    end

    assert_not PushSubscription.exists?(@subscription.id)
  end

  test "410 응답이면 구독을 삭제한다" do
    response = Struct.new(:code, :body).new("410", "expired")
    error = WebPush::ResponseError.new(response, "example.com")

    Configs::WebPush.stub(:configured?, true) do
      Configs::WebPush.stub(:subject, "mailto:admin@example.com") do
        Configs::WebPush.stub(:public_key, "public") do
          Configs::WebPush.stub(:private_key, "private") do
            WebPush.stub(:payload_send, ->(**_kwargs) { raise error }) do
              @service.notify_user(user: @user, title: "title", body: "body", path: "/articles/test")
            end
          end
        end
      end
    end

    assert_not PushSubscription.exists?(@subscription.id)
  end

  test "VAPID public key mismatch 401이면 구독을 삭제한다" do
    response = Struct.new(:code, :body).new("401", "{\"message\":\"VAPID public key mismatch\"}")
    error = WebPush::Unauthorized.new(response, "updates.push.services.mozilla.com")

    Configs::WebPush.stub(:configured?, true) do
      Configs::WebPush.stub(:subject, "mailto:admin@example.com") do
        Configs::WebPush.stub(:public_key, "public") do
          Configs::WebPush.stub(:private_key, "private") do
            WebPush.stub(:payload_send, ->(**_kwargs) { raise error }) do
              @service.notify_user(user: @user, title: "title", body: "body", path: "/articles/test")
            end
          end
        end
      end
    end

    assert_not PushSubscription.exists?(@subscription.id)
  end
end
