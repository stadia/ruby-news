# frozen_string_literal: true

require "test_helper"
require "opentelemetry-logs-sdk"

class OtelLogAppenderTest < ActiveSupport::TestCase
  setup do
    @exporter = OpenTelemetry::SDK::Logs::Export::InMemoryLogRecordExporter.new
    provider = OpenTelemetry::SDK::Logs::LoggerProvider.new
    provider.add_log_record_processor(OpenTelemetry::SDK::Logs::Export::SimpleLogRecordProcessor.new(@exporter))
    # appender는 생성 시점의 전역 provider를 잡으므로, 전역을 바꾸지 않고 그 순간만 바꿔 끼운다.
    @appender = OpenTelemetry.stub(:logger_provider, provider) { OtelLogAppender.new(metrics: false) }
  end

  test "body는 메시지 문자열만 담고 메타데이터는 attributes로 평탄화한다" do
    record = emit("ArticlesController", message: "Completed #show", duration: 55.2,
                  metric: "rails.controller.process_action",
                  payload: { method: "GET", path: "/articles/1", status: 200, db_runtime: 1.5 })

    assert_equal "Completed #show", record.body
    assert_equal "INFO", record.severity_text
    assert_equal({
      "code.namespace" => "ArticlesController",
      "metric" => "rails.controller.process_action",
      "duration_ms" => 55.2,
      "request_id" => "req-1",
      "client.address" => "1.2.3.4",
      "http.request.method" => "GET",
      "url.path" => "/articles/1",
      "http.response.status_code" => 200,
      "db_runtime" => 1.5
    }, record.attributes)
  end

  test "예외는 OTel semconv exception.* 속성으로 보낸다" do
    error = begin
      begin
        raise ArgumentError, "원인"
      rescue ArgumentError
        raise RuntimeError, "실패"
      end
    rescue RuntimeError => e
      e
    end

    record = emit("Rails", message: "boom", exception: error, level: :error)

    assert_equal "ERROR", record.severity_text
    assert_equal OpenTelemetry::Logs::SeverityNumber::SEVERITY_NUMBER_ERROR, record.severity_number
    assert_equal "RuntimeError", record.attributes["exception.type"]
    assert_equal "실패", record.attributes["exception.message"]
    assert_includes record.attributes["exception.stacktrace"], "otel_log_appender_test.rb"
    assert_equal "ArgumentError: 원인", record.attributes["exception.cause"]
  end

  test "severity_number는 OTel 표준 번호(INFO=9)로 보낸다" do
    record = emit("Rails", message: "hi")

    assert_equal OpenTelemetry::Logs::SeverityNumber::SEVERITY_NUMBER_INFO, record.severity_number
  end

  test "일반 tags와 metric_amount를 보존하고 named tag 원시 타입을 유지한다" do
    record = emit("Rails", message: "m", metric: "jobs.done", metric_amount: 100,
                  named_tags: { retry: 2, admin: true }, tags: %w[web canary])

    assert_equal 100, record.attributes["metric_amount"]
    assert_equal %w[web canary], record.attributes["tags"]
    assert_equal 2, record.attributes["retry"]
    assert_same true, record.attributes["admin"]
  end

  test "payload가 기준 필드와 겹치면 기준 필드를 지키고 payload 값은 payload.* 로 남긴다" do
    record = emit("ArticlesController", message: "m",
                  payload: { request_id: "spoofed", "code.namespace": "Other" })

    assert_equal "req-1", record.attributes["request_id"]
    assert_equal "ArticlesController", record.attributes["code.namespace"]
    assert_equal "spoofed", record.attributes["payload.request_id"]
    assert_equal "Other", record.attributes["payload.code.namespace"]
  end

  private

  def emit(name, level: :info, named_tags: {}, tags: [], **fields)
    log = SemanticLogger.tagged(*tags) do
      SemanticLogger.tagged(request_id: "req-1", ip: "1.2.3.4", **named_tags) { SemanticLogger::Log.new(name, level) }
    end
    log.assign(**fields)
    @appender.log(log)
    @exporter.emitted_log_records.last
  end
end
