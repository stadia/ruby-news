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
    assert_equal "RuntimeError", record.attributes["exception.type"]
    assert_equal "실패", record.attributes["exception.message"]
    assert_includes record.attributes["exception.stacktrace"], "otel_log_appender_test.rb"
    assert_equal "ArgumentError: 원인", record.attributes["exception.cause"]
  end

  private

  def emit(name, level: :info, **fields)
    log = SemanticLogger.tagged(request_id: "req-1", ip: "1.2.3.4") { SemanticLogger::Log.new(name, level) }
    log.assign(**fields)
    @appender.log(log)
    @exporter.emitted_log_records.last
  end
end
