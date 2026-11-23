# frozen_string_literal: true

require "test_helper"

class GmailArticleJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "enqueue_all이 Site.kept.gmail의 ID를 예약한다" do
    assert_enqueued_with(job: GmailArticleJob, args: [ Site.kept.gmail.order("id ASC").pluck(:id) ]) do
      GmailArticleJob.enqueue_all
    end
  end

  test "GmailArticleJob은 LinkHelper를 포함한다" do
    assert_includes GmailArticleJob.ancestors, LinkHelper
  end

  test "빈 ID 배열은 오류 없이 종료한다" do
    assert_nothing_raised { GmailArticleJob.perform_now([]) }
  end

  test "클라이언트 초기화 실패 시 last_checked_at을 갱신하지 않는다" do
    site = sites(:newsletter)
    site.update!(email: "bot@example.com")
    original_checked_at = site.last_checked_at
    site.define_singleton_method(:init_client) { nil }

    Site.stub(:find_by, site) do
      assert_nothing_raised { GmailArticleJob.perform_now([ site.id ]) }
    end

    assert_equal original_checked_at, site.reload.last_checked_at
  end

  test "클라이언트 초기화 성공 시 메일 조회 후 last_checked_at을 갱신한다" do
    site = sites(:newsletter)
    site.update!(email: "bot@example.com", last_checked_at: 2.days.ago)
    client = Gmail.allocate
    client.define_singleton_method(:fetch_email_links) { |*_args, **_kwargs| [] }
    site.define_singleton_method(:init_client) { client }

    Site.stub(:find_by, site) do
      GmailArticleJob.perform_now([ site.id ])
    end

    assert_operator site.reload.last_checked_at, :>, 1.minute.ago
  end

  test "등록이 거부되는 링크가 있어도 나머지 처리를 계속한다" do
    site = sites(:newsletter)
    site.update!(email: "bot@example.com", last_checked_at: 2.days.ago)
    client = Gmail.allocate
    users(:john).update_columns(username: "bot") # create_article은 bot 사용자로 기사를 만든다
    client.define_singleton_method(:fetch_email_links) { |*_args, **_kwargs| [ "http://10.0.0.5/internal-link" ] }
    site.define_singleton_method(:init_client) { client }

    Site.stub(:find_by, site) do
      assert_nothing_raised { GmailArticleJob.perform_now([ site.id ]) }
    end

    assert_operator site.reload.last_checked_at, :>, 1.minute.ago
  end

  test "삭제된 사이트는 건너뛰고 나머지 ID로 체인을 이어간다" do
    missing_id = Site.maximum(:id).to_i + 1000

    assert_enqueued_with(job: GmailArticleJob, args: [ [ 1, 2 ] ]) do
      assert_nothing_raised { GmailArticleJob.perform_now([ missing_id, 1, 2 ]) }
    end
  end

  test "DB 연결 오류로 재시도하면 처리하던 사이트 ID를 그대로 다시 예약한다" do
    raise_connection_error = ->(*) { raise ActiveRecord::ConnectionNotEstablished, "down" }

    Site.stub(:find_by, raise_connection_error) do
      assert_enqueued_with(job: GmailArticleJob, args: [ [ 1, 2 ] ]) do
        GmailArticleJob.perform_now([ 1, 2 ])
      end
    end
  end

  test "링크의 최종 URL이 기존 기사와 같으면 잡을 실패시키지 않고 체크포인트를 갱신한다" do
    User.first.update_columns(username: "bot") # 잡은 bot 계정으로 기사를 만든다
    existing = articles(:ruby_article)
    site = sites(:newsletter)
    site.update!(email: "bot@example.com", last_checked_at: 2.days.ago)
    client = Gmail.allocate
    client.define_singleton_method(:fetch_email_links) { |*_args, **_kwargs| [ "https://links.newsletter.dev/c/abc123" ] }
    site.define_singleton_method(:init_client) { client }
    redirect_to_existing = Object.new
    redirect_to_existing.define_singleton_method(:call) do |article|
      article.url = existing.url
      Dry::Monads::Success(article)
    end

    Site.stub(:find_by, site) do
      Articles::MetadataPreparationService.stub(:new, ->(*) { redirect_to_existing }) do
        assert_nothing_raised { GmailArticleJob.perform_now([ site.id ]) }
      end
    end

    assert_operator site.reload.last_checked_at, :>, 1.minute.ago
  end

  # 다른 잡이 exists? 확인과 INSERT 사이에 같은 최종 url을 먼저 저장한 경합(exists?를 false로 고정해 흉내 낸다).
  test "동시 저장으로 url 유니크 인덱스에 걸려도 잡을 실패시키지 않는다" do
    User.first.update_columns(username: "bot")
    existing = articles(:ruby_article)
    site = sites(:newsletter)
    site.update!(email: "bot@example.com", last_checked_at: 2.days.ago)
    client = Gmail.allocate
    client.define_singleton_method(:fetch_email_links) { |*_args, **_kwargs| [ "https://links.newsletter.dev/c/race" ] }
    site.define_singleton_method(:init_client) { client }
    redirect_to_existing = Object.new
    redirect_to_existing.define_singleton_method(:call) do |article|
      article.url = existing.url
      Dry::Monads::Success(article)
    end

    Site.stub(:find_by, site) do
      Article.stub(:exists?, false) do
        Articles::MetadataPreparationService.stub(:new, ->(*) { redirect_to_existing }) do
          assert_nothing_raised { GmailArticleJob.perform_now([ site.id ]) }
        end
      end
    end

    assert_operator site.reload.last_checked_at, :>, 1.minute.ago
  end
end
