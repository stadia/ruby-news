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
    local_actor = users(:john).fedipub_actor
    local_likees_before = local_actor.reload.likees_count
    Like.create!(actor: local_actor, likeable: article)

    perform_enqueued_jobs { DiscardedArticleCleanupJob.perform_now }

    assert_not ActsAsTaggableOn::Tagging.exists?(taggable_type: "Article", taggable_id: article.id)
    assert_equal 1, ActsAsTaggableOn::Tag.find_by!(name: "cleanup-shared-tag").taggings_count
    assert_not Like.exists?(likeable_type: "Article", likeable_id: article.id)
    assert_not Boost.exists?(boostable_type: "Article", boostable_id: article.id)
    assert_equal 1, actor.reload.likees_count
    assert_equal 0, actor.boostees_count
    # 로컬 actor의 좋아요도 Undo 연합 없이 지우고 카운터만 되돌린다.
    assert_equal local_likees_before, local_actor.reload.likees_count
    assert_not ActiveStorage::Blob.exists?(filename: "thumb.png")
    assert_not ActiveStorage::Attachment.exists?(record_type: "Article", record_id: article.id)
  end

  # 폐기 기사에도 좋아요가 허용되므로, 정리 도중 커밋된 좋아요가 카운터를 어긋나게 해선 안 된다.
  # 반응 행을 처음 건드리는 쿼리 직후에 좋아요를 끼워 넣어, 개수 조회와 삭제 사이의 경쟁을 재현한다.
  test "정리 도중 끼어든 좋아요가 있어도 actor 카운터는 실제 행 수와 맞는다" do
    article = articles(:deleted_article)
    article.update_columns(created_at: 7.months.ago, deleted_at: 7.months.ago)
    actor = users(:john).fedipub_actor
    Like.create!(actor:, likeable: article)

    injected = false
    callback = lambda do |*, payload|
      next if injected || !payload[:sql].match?(/\A(SELECT COUNT|DELETE)\b.*"likes"/m)

      injected = true
      Like.create!(actor: users(:jane).fedipub_actor, likeable: article)
    end

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      DiscardedArticleCleanupJob.perform_now
    end

    assert injected, "반응 행을 건드리는 쿼리가 실행돼야 한다"
    [ actor, users(:jane).fedipub_actor ].each do |a|
      assert_equal Like.where(actor: a).count, a.reload.likees_count, "actor #{a.id}"
    end
  end
end
