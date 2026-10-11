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

    Site.stub(:find, site) do
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

    Site.stub(:find, site) do
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

    Site.stub(:find, site) do
      assert_nothing_raised { GmailArticleJob.perform_now([ site.id ]) }
    end

    assert_operator site.reload.last_checked_at, :>, 1.minute.ago
  end
end
