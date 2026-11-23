# frozen_string_literal: true

require "test_helper"

class YoutubeSiteJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "YouTube API 쿼터 초과 오류는 job을 실패시키지 않는다" do
    error = youtube_quota_exceeded_error
    client = Youtube::Channel.allocate
    client.define_singleton_method(:videos) do
      raise error
    end

    site = Object.new
    site.define_singleton_method(:init_client) { client }

    site.define_singleton_method(:update) do |**|
      flunk "쿼터 초과 시 last_checked_at을 갱신하면 안 된다"
    end

    Site.stub(:find_by, site) do
      assert_no_enqueued_jobs do
        assert_nothing_raised do
          YoutubeSiteJob.perform_now([ 123, 456 ])
        end
      end
    end
  end

  # perform의 인자는 큐에서 역직렬화돼 들어오므로 시그니처가 배열을 보장하지 못한다.
  # 단일 id로 enqueue된 잡도 받아들여야 한다.
  test "단일 id로 enqueue돼도 배열로 승격해 처리한다" do
    site = Object.new
    site.define_singleton_method(:init_client) { Object.new }

    Site.stub(:find_by, site) do
      assert_no_enqueued_jobs do
        assert_nothing_raised do
          YoutubeSiteJob.perform_now(123)
        end
      end
    end
  end

  test "enqueue_all이 Site.kept.youtube의 ID를 예약한다" do
    assert_enqueued_with(job: YoutubeSiteJob, args: [ Site.kept.youtube.order("id ASC").pluck(:id) ]) do
      YoutubeSiteJob.enqueue_all
    end
  end

  test "YOUTUBE_NORMALIZED_HOST가 www.youtube.com이다" do
    assert_equal "www.youtube.com", YoutubeSiteJob::YOUTUBE_NORMALIZED_HOST
  end

  private

  def youtube_quota_exceeded_error
    response_body = {
      "error" => {
        "code" => 429,
        "message" => "Quota exceeded",
        "errors" => [ { "reason" => "rateLimitExceeded" } ],
        "status" => "RESOURCE_EXHAUSTED"
      }
    }

    Yt::Errors::RequestError.new({ "response_body" => response_body }.to_json)
  end

  test "삭제된 사이트는 건너뛰고 나머지 ID로 체인을 이어간다" do
    missing_id = Site.maximum(:id).to_i + 1000

    assert_enqueued_with(job: YoutubeSiteJob, args: [ [ 1, 2 ] ]) do
      assert_nothing_raised { YoutubeSiteJob.perform_now([ missing_id, 1, 2 ]) }
    end
  end

  test "YouTube 클라이언트를 만들지 못한 사이트는 건너뛰고 체인을 이어간다" do
    site = Object.new
    site.define_singleton_method(:init_client) { nil }

    site.define_singleton_method(:update) { |**| flunk "조회하지 못했으면 last_checked_at을 갱신하면 안 된다" }

    Site.stub(:find_by, site) do
      assert_enqueued_with(job: YoutubeSiteJob, args: [ [ 456 ] ]) do
        YoutubeSiteJob.perform_now([ 123, 456 ])
      end
    end
  end

  test "영상 목록을 받지 못한 사이트는 건너뛰고 체인을 이어간다" do
    client = Youtube::Channel.allocate
    client.define_singleton_method(:videos) { nil }
    site = Object.new
    site.define_singleton_method(:init_client) { client }

    site.define_singleton_method(:update) { |**| flunk "조회하지 못했으면 last_checked_at을 갱신하면 안 된다" }

    Site.stub(:find_by, site) do
      assert_enqueued_with(job: YoutubeSiteJob, args: [ [ 456 ] ]) do
        YoutubeSiteJob.perform_now([ 123, 456 ])
      end
    end
  end
end
