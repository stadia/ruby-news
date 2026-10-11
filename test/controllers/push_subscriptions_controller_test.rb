# frozen_string_literal: true

require "test_helper"

class PushSubscriptionsControllerTest < ActionDispatch::IntegrationTest
  test "POST create saves push subscription for signed-in user" do
    user = users(:john)
    sign_in_as(user)

    assert_difference("PushSubscription.count", 1) do
      post push_subscription_path, params: {
        push_subscription: {
          endpoint: "https://fcm.googleapis.com/fcm/send/new-subscription",
          p256dh: "BNew6eEl6eEl6eEl6eEl6eEl6eEl6eEl6eEl6eEl6eA",
          auth: "bmV3QXV0aEtleQ"
        }
      }
    end

    assert_response :ok
  end

  test "POST create updates existing subscription" do
    user = users(:john)
    sign_in_as(user)
    existing = push_subscriptions(:john_browser)

    assert_no_difference("PushSubscription.count") do
      post push_subscription_path, params: {
        push_subscription: {
          endpoint: existing.endpoint,
          p256dh: "BUpdatedKey",
          auth: "dXBkYXRlZEF1dGg"
        }
      }
    end

    assert_response :ok
  end

  test "POST create rejects endpoint outside trusted push services" do
    sign_in_as(users(:john))

    assert_no_difference("PushSubscription.count") do
      post push_subscription_path, params: {
        push_subscription: { endpoint: "https://evil.example/push", p256dh: "BKey", auth: "BAuth" }
      }
    end

    assert_response :unprocessable_entity
  end

  test "POST create redirects to login for unauthenticated user" do
    post push_subscription_path, params: {
      push_subscription: {
        endpoint: "https://example.com/push",
        p256dh: "BKey",
        auth: "BAuth"
      }
    }

    assert_redirected_to new_user_session_path
  end

  test "POST create returns unprocessable_entity for invalid params" do
    user = users(:john)
    sign_in_as(user)

    post push_subscription_path, params: {
      push_subscription: {
        endpoint: "",
        p256dh: "",
        auth: ""
      }
    }

    assert_response :unprocessable_entity
  end

  test "DELETE destroy removes push subscription for signed-in user" do
    user = users(:john)
    sign_in_as(user)
    existing = push_subscriptions(:john_browser)

    assert_difference("PushSubscription.count", -1) do
      delete push_subscription_path, params: { endpoint: existing.endpoint }
    end

    assert_response :no_content
  end

  test "DELETE destroy with nested params removes subscription" do
    user = users(:john)
    sign_in_as(user)
    existing = push_subscriptions(:john_browser)

    assert_difference("PushSubscription.count", -1) do
      delete push_subscription_path, params: { push_subscription: { endpoint: existing.endpoint } }
    end

    assert_response :no_content
  end

  test "DELETE destroy redirects to login for unauthenticated user" do
    delete push_subscription_path, params: { endpoint: "https://example.com/push" }

    assert_redirected_to new_user_session_path
  end

  test "DELETE destroy returns bad request without endpoint" do
    user = users(:john)
    sign_in_as(user)

    delete push_subscription_path

    assert_response :bad_request
  end
end
