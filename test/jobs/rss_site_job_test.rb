# frozen_string_literal: true

require "test_helper"

class RssSiteJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "enqueue_all이 Site.kept.rss의 ID를 예약한다" do
    assert_enqueued_with(job: RssSiteJob, args: [ Site.kept.rss.order("id ASC").pluck(:id) ]) do
      RssSiteJob.enqueue_all
    end
  end

  test "RssSiteJob은 RssHelper를 포함한다" do
    assert_includes RssSiteJob.ancestors, RssHelper
  end

  test "DB 연결 오류로 재시도하면 처리하던 사이트 ID를 그대로 다시 예약한다" do
    raise_connection_error = ->(*) { raise ActiveRecord::ConnectionNotEstablished, "down" }

    Site.stub(:kept, raise_connection_error) do
      assert_enqueued_with(job: RssSiteJob, args: [ [ 1, 2 ] ]) do
        RssSiteJob.perform_now([ 1, 2 ])
      end
    end
  end

  test "피드를 받지 못한 사이트 뒤에는 다음 잡을 한 번만 예약한다" do
    site = Site.kept.rss.first
    job = RssSiteJob.new([ site.id, 2 ])
    job.define_singleton_method(:fetch_feed) { |_site| nil }

    assert_enqueued_jobs 1, only: RssSiteJob do
      job.perform_now
    end
  end
end
