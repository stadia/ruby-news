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
                  metric: "rails.controller.process_action", named_tags: REQUEST_TAGS,
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
    }, record.attributes.except("thread.name"))
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

  test "OTel이 받지 않는 숫자 타입(BigDecimal)의 named tag는 문자열로 보낸다" do
    record = emit("Rails", message: "m", named_tags: { amount: BigDecimal("1.5") })

    assert_equal BigDecimal("1.5").to_s, record.attributes["amount"]
  end

  test "payload가 기준 필드와 겹치면 기준 필드를 지키고 payload 값은 payload.* 로 남긴다" do
    record = emit("ArticlesController", message: "m", named_tags: REQUEST_TAGS,
                  payload: { request_id: "spoofed", "code.namespace": "Other" })

    assert_equal "req-1", record.attributes["request_id"]
    assert_equal "ArticlesController", record.attributes["code.namespace"]
    assert_equal "spoofed", record.attributes["payload.request_id"]
    assert_equal "Other", record.attributes["payload.code.namespace"]
  end

  test "named_tags·payload가 없는 로그(잡·부팅)는 code.namespace만 보낸다" do
    record = emit("Rails", message: "boot")

    assert_equal "boot", record.body
    assert_equal({ "code.namespace" => "Rails" }, record.attributes.except("thread.name"))
  end

  test "cause 없는 예외는 exception.cause를 만들지 않는다" do
    error = begin
      raise ArgumentError, "단독"
    rescue ArgumentError => e
      e
    end

    record = emit("Rails", message: "boom", exception: error, level: :error)

    assert_equal "ArgumentError", record.attributes["exception.type"]
    assert_equal error.backtrace.join("\n"), record.attributes["exception.stacktrace"]
    assert_not record.attributes.key?("exception.cause")
  end

  test "error 로그는 호출 위치와 스레드를 code.filepath·code.lineno·thread.name으로 남긴다" do
    # 예외 없는 logger.error도 backtrace_level(:error) 이상이면 호출 위치가 잡힌다.
    record = Thread.new do
      Thread.current.name = "worker-1"
      emit("Rails", message: "boom", level: :error)
    end.value

    assert_equal "worker-1", record.attributes["thread.name"]
    assert record.attributes["code.filepath"].end_with?("otel_log_appender_test.rb")
    assert_kind_of Integer, record.attributes["code.lineno"]
  end

  test "로그 호출 시점의 OTel 컨텍스트로 trace_id·span_id를 잇는다" do
    # appender는 Processor 스레드에서 돌아 Context.current가 비어 있다. 호출 시점 컨텍스트만이 트레이스와 잇는 경로다.
    span_context = OpenTelemetry::Trace::SpanContext.new
    context = OpenTelemetry::Trace.context_with_span(OpenTelemetry::Trace.non_recording_span(span_context))

    record = emit("Rails", message: "m", context: context)

    assert_equal span_context.trace_id, record.trace_id
    assert_equal span_context.span_id, record.span_id
  end

  private

  REQUEST_TAGS = { request_id: "req-1", ip: "1.2.3.4" }.freeze

  def emit(name, level: :info, named_tags: {}, tags: [], context: nil, **fields)
    log = SemanticLogger.tagged(*tags) do
      SemanticLogger.tagged(**named_tags) { SemanticLogger::Log.new(name, level) }
    end
    log.set_context(:open_telemetry, context) if context
    log.assign(**fields)
    @appender.log(log)
    @exporter.emitted_log_records.last
  end
end
