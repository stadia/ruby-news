# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

class DiscardedArticleCleanupJob < ApplicationJob
  queue_as :default

  BATCH_SIZE = 500
  RETENTION_PERIOD = 6.months

  #: () -> void
  def perform
    cutoff = RETENTION_PERIOD.ago
    scope = Article.discarded.where(created_at: ...cutoff)
    nulled_posts_count = 0
    deleted_notifications_count = 0
    deleted_articles_count = 0

    logger.info("DiscardedArticleCleanupJob started: cutoff=#{cutoff.iso8601}, batch_size=#{BATCH_SIZE}, target_count=#{scope.count}")

    scope.in_batches(of: BATCH_SIZE) do |batch|
      article_ids = batch.pluck(:id)
      next if article_ids.empty?

      # `update_all`/`delete_all` are typed `untyped` by the activerecord RBS,
      # so `count += rows` resolves against every `Integer#+` overload and
      # widens the counters to BigDecimal. Both actually return a row count.
      cleanup_dependents(article_ids)
      nulled_posts = Post.where(article_id: article_ids).update_all(article_id: nil) #: Integer
      deleted_notifications = NotificationDelivery.where(article_id: article_ids).delete_all #: Integer
      deleted_articles = Article.where(id: article_ids).delete_all #: Integer

      nulled_posts_count += nulled_posts
      deleted_notifications_count += deleted_notifications
      deleted_articles_count += deleted_articles

      logger.info(
        "DiscardedArticleCleanupJob batch completed: article_ids=#{article_ids.size}, nulled_posts=#{nulled_posts}, deleted_notifications=#{deleted_notifications}, deleted_articles=#{deleted_articles}"
      )
    end

    vacuum_articles if deleted_articles_count.positive?

    logger.info(
      "DiscardedArticleCleanupJob finished: deleted_articles=#{deleted_articles_count}, deleted_notifications=#{deleted_notifications_count}, nulled_posts=#{nulled_posts_count}, vacuum_run=#{deleted_articles_count.positive?}"
    )
  end

  private

  # 기사를 delete_all로 지우면 콜백이 돌지 않으므로, 다형 연관(FK 없음)과 첨부를 먼저 정리한다.
  #: (Array[Integer] article_ids) -> void
  def cleanup_dependents(article_ids)
    # destroy_all이라야 tags.taggings_count가 줄어든다.
    taggings = ActsAsTaggableOn::Tagging.where(taggable_type: "Article", taggable_id: article_ids).destroy_all.size
    likes = delete_reactions(Like.where(likeable_type: "Article", likeable_id: article_ids), :likees_count)
    boosts = delete_reactions(Boost.where(boostable_type: "Article", boostable_id: article_ids), :boostees_count)
    attachments = purge_attachments(article_ids)

    logger.info(
      "DiscardedArticleCleanupJob dependents cleaned: taggings=#{taggings}, likes=#{likes}, boosts=#{boosts}, attachments=#{attachments}"
    )
  end

  # 지워질 기사에 대한 Undo 연합 발송은 필요 없으므로 delete_all로 지우고 actor 카운터만 맞춘다.
  # 카운터 감소와 삭제를 한 트랜잭션으로 묶어, 도중 실패 후 재실행이 같은 행을 다시 빼지 않게 한다.
  #: (ActiveRecord::Relation scope, Symbol counter) -> Integer
  def delete_reactions(scope, counter)
    ActiveRecord::Base.transaction do
      scope.group(:actor_id).count.each do |actor_id, count|
        Fedipub::Actor.update_counters(actor_id, counter => -count)
      end
      scope.delete_all
    end
  end

  # Attachment#purge_later는 record.touch를 해 곧 지울 기사에 UPDATE와 콜백을 일으키므로, 행만 지우고 blob을 넘긴다.
  #: (Array[Integer] article_ids) -> Integer
  def purge_attachments(article_ids)
    count = 0
    ActiveStorage::Attachment.where(record_type: "Article", record_id: article_ids).includes(:blob).find_each do |attachment|
      attachment.delete
      attachment.blob&.purge_later
      count += 1
    end
    count
  end

  #: () -> void
  def vacuum_articles
    Article.connection_pool.with_connection do |connection|
      if connection.transaction_open?
        logger.warn("DiscardedArticleCleanupJob skipped vacuum: open transaction")
        return
      end

      connection.execute("VACUUM ANALYZE #{Article.quoted_table_name}")
      logger.info("DiscardedArticleCleanupJob vacuum completed for #{Article.table_name}")
    end
  end
end
