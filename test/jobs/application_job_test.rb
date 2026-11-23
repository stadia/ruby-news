# frozen_string_literal: true

require "test_helper"

class ApplicationJobTest < ActiveJob::TestCase
  class RaisingJob < ApplicationJob
    ERRORS = {
      "connection" => ActiveRecord::ConnectionNotEstablished,
      "unhandled" => ArgumentError
    }.freeze

    def perform(kind)
      raise ERRORS.fetch(kind), "boom"
    end
  end

  test "DB 연결 오류는 다시 던지지 않고 지연 재시도 한 건을 큐에 넣는다" do
    assert_enqueued_jobs 1, only: RaisingJob do
      RaisingJob.perform_now("connection")
    end

    assert enqueued_jobs.last[:at], "지연 없이 즉시 재시도됨"
  end

  test "처리 정책이 없는 예외는 로그를 남기고 다시 던진다" do
    log = StringIO.new
    original_logger = ActiveJob::Base.logger
    ActiveJob::Base.logger = ActiveSupport::Logger.new(log)
    begin
      assert_raises(ArgumentError) { RaisingJob.perform_now("unhandled") }
    ensure
      ActiveJob::Base.logger = original_logger
    end

    assert_includes log.string, "Job failed: #{RaisingJob.name}"
    assert_no_enqueued_jobs only: RaisingJob
  end
end
