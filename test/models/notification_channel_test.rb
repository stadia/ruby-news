# frozen_string_literal: true

require "test_helper"

class NotificationChannelTest < ActiveSupport::TestCase
  test "delivery_ready는 discarded channel을 제외한다" do
    channel = notification_channels(:acme_discord)
    channel.discard

    assert_not_includes NotificationChannel.active, channel
    assert_not_includes NotificationChannel.delivery_ready, channel
  end

  test "delivery가 있는 channel은 destroy할 수 없다" do
    channel = notification_channels(:acme_slack)

    assert_not channel.destroy
    assert_predicate channel.errors[:base], :any?
  end

  test "ensure_relink_allowed!는 새 레코드와 같은 채널 재연동을 허용한다" do
    channel = notification_channels(:acme_slack)

    assert_nil SlackChannel.new.ensure_relink_allowed!("CANY")
    assert_nil channel.ensure_relink_allowed!(channel.channel_id)
  end

  test "ensure_relink_allowed!는 다른 채널로의 재연동을 channel_changed로 거절한다" do
    channel = notification_channels(:acme_slack)

    error = assert_raises(NotificationChannel::RelinkRejected) { channel.ensure_relink_allowed!("COTHER") }

    assert_equal :channel_changed, error.reason
  end

  test "ensure_relink_allowed!는 삭제된 채널 재연동을 discarded로 거절한다" do
    channel = notification_channels(:acme_slack)
    channel.discard

    error = assert_raises(NotificationChannel::RelinkRejected) { channel.ensure_relink_allowed!(channel.channel_id) }

    assert_equal :discarded, error.reason
  end
end
