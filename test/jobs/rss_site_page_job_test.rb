# frozen_string_literal: true

require "test_helper"

class RssSitePageJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "enqueue_all이 Site.kept.rss_page의 ID를 예약한다" do
    assert_enqueued_with(job: RssSitePageJob, args: [ Site.kept.rss_page.order("id ASC").pluck(:id) ]) do
      RssSitePageJob.enqueue_all
    end
  end

  test "RssSitePageJob은 RssHelper와 LinkHelper를 포함한다" do
    assert_includes RssSitePageJob.ancestors, RssHelper
    assert_includes RssSitePageJob.ancestors, LinkHelper
  end

  test "빈 ID 배열은 오류 없이 종료한다" do
    assert_nothing_raised { RssSitePageJob.perform_now([]) }
  end

  test "삭제된 사이트는 건너뛰고 나머지 ID로 체인을 이어간다" do
    missing_id = Site.maximum(:id).to_i + 1000

    assert_enqueued_with(job: RssSitePageJob, args: [ [ 1, 2 ] ]) do
      assert_nothing_raised { RssSitePageJob.perform_now([ missing_id, 1, 2 ]) }
    end
  end
end
