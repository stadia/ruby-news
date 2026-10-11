# frozen_string_literal: true

require "test_helper"

class DiscardedArticleCleanupJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "6개월이 지난 discarded article만 정리한다" do
    old_discarded_article = articles(:deleted_article)
    old_discarded_article.update_columns(created_at: 7.months.ago, deleted_at: 7.months.ago)

    recent_discarded_article = Article.new(
      title: "최근 삭제 기사",
      url: "https://example.com/recent-discarded-article",
      origin_url: "https://example.com/recent-discarded-article",
      user: users(:john),
      site: sites(:ruby_weekly)
    )
    recent_discarded_article.stub(:generate_metadata, nil) { recent_discarded_article.save! }
    recent_discarded_article.update_columns(deleted_at: 1.week.ago)

    old_kept_article = Article.new(
      title: "오래된 일반 기사",
      url: "https://example.com/old-kept-article",
      origin_url: "https://example.com/old-kept-article",
      user: users(:john),
      site: sites(:ruby_weekly)
    )
    old_kept_article.stub(:generate_metadata, nil) { old_kept_article.save! }
    old_kept_article.update_columns(created_at: 7.months.ago)

    comment = Post.create!(body: "정리 대상 댓글", user: users(:john), article: old_discarded_article)
    delivery = NotificationDelivery.create!(
      type: "SlackDelivery",
      article: old_discarded_article,
      notification_channel: notification_channels(:globex_slack),
      channel_id: "CLEANUP",
      channel_name: "cleanup",
      status: "sent"
    )

    DiscardedArticleCleanupJob.perform_now

    assert_not Article.exists?(old_discarded_article.id)
    assert Article.exists?(recent_discarded_article.id)
    assert Article.exists?(old_kept_article.id)
    assert_nil comment.reload.article_id
    assert_not NotificationDelivery.exists?(delivery.id)
  end

  # delete_all은 콜백을 건너뛰므로 다형 연관·태그 카운터·첨부를 따로 정리해야 한다(#1061).
  test "정리한 기사의 태그·좋아요·부스트·썸네일도 함께 정리한다" do
    article = articles(:deleted_article)
    article.update_columns(created_at: 7.months.ago, deleted_at: 7.months.ago)
    article.tag_list.add("cleanup-only-tag", "cleanup-shared-tag")
    article.save!(validate: false)
    other = articles(:ruby_article)
    other.tag_list.add("cleanup-shared-tag")
    other.save!(validate: false)
    article.thumbnail.attach(io: StringIO.new("img"), filename: "thumb.png", content_type: "image/png")

    actor = Fedipub::Actor.create!(
      federated_url: "https://remote.example/users/cleaner-#{SecureRandom.hex(4)}",
      username: "cleaner", name: "Cleaner", server: "remote.example",
      inbox_url: "https://remote.example/inbox", outbox_url: "https://remote.example/outbox",
      followers_url: "https://remote.example/followers", followings_url: "https://remote.example/following",
      profile_url: "https://remote.example/@cleaner", actor_type: "Person", local: false
    )
    Like.create!(actor:, likeable: article)
    Boost.create!(actor:, boostable: article)
    Like.create!(actor:, likeable: other)

    perform_enqueued_jobs { DiscardedArticleCleanupJob.perform_now }

    assert_not ActsAsTaggableOn::Tagging.exists?(taggable_type: "Article", taggable_id: article.id)
    assert_equal 1, ActsAsTaggableOn::Tag.find_by!(name: "cleanup-shared-tag").taggings_count
    assert_not Like.exists?(likeable_type: "Article", likeable_id: article.id)
    assert_not Boost.exists?(boostable_type: "Article", boostable_id: article.id)
    assert_equal 1, actor.reload.likees_count
    assert_equal 0, actor.boostees_count
    assert_not ActiveStorage::Attachment.exists?(record_type: "Article", record_id: article.id)
  end
end
