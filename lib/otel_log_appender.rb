# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

require "semantic_logger/appender/open_telemetry"

# SigNoz(ClickHouse logs_v2)에서 검색과 인덱스가 먹히는 모양으로 LogRecord를 보낸다.
# 기본 appender는 payload를 뺀 나머지(message·name·named_tags·duration·exception·host·pid …)를
# Hash째 body에 넣고, SigNoz는 이를 JSON 문자열로 저장해 body 인덱스가 메타데이터를 색인하고 맵 인덱스는 못 탄다.
# body에는 message만 두고, 나머지는 typed attributes(attributes_string/number/bool 맵)로 평탄화한다.
# application·environment는 resource(service.name·deployment.environment)와 중복이라 버린다.
# host·pid는 resource에 없지만 버린다. 필요해지면 attributes에 추가한다.
class OtelLogAppender < SemanticLogger::Appender::OpenTelemetry
  # 요청 완료 로그(Completed)의 method·path·status만 semconv 키로 바꾼다(rack span 키와 같다).
  # 다른 로그의 payload status·path는 도메인 값이라 그대로 둔다.
  REQUEST_METRIC = "rails.controller.process_action"
  HTTP_RENAMES = {
    "method" => "http.request.method",
    "path" => "url.path",
    "status" => "http.response.status_code"
  }.freeze
  TAG_RENAMES = { "ip" => "client.address" }.freeze

  # @rbs log: SemanticLogger::Log
  # @rbs return: bool
  def log(log)
    record = formatter.call(log, self)

    @logger.on_emit(
      severity_text: record[:level].upcase,
      severity_number: record[:level_index],
      timestamp: record[:time],
      body: record[:message],
      attributes: attributes(record),
      context: log.context&.dig(:open_telemetry) || ::OpenTelemetry::Context.current
    )
    true
  end

  private

  # @rbs record: Hash[Symbol, untyped]
  # @rbs return: Hash[String, untyped]
  def attributes(record)
    attrs = {
      "code.namespace" => record[:name],
      "metric" => record[:metric],
      "metric_amount" => record[:metric_amount],
      "duration_ms" => record[:duration_ms],
      "tags" => record[:tags]&.map(&:to_s),
      # 호출 위치는 backtrace_level(:error) 이상에서만 잡힌다. 예외 없는 error 로그의 유일한 위치 정보다.
      "code.filepath" => record[:file],
      "code.lineno" => record[:line],
      "thread.name" => record[:thread]
    }.compact
    record[:named_tags]&.each { |key, value| attrs[TAG_RENAMES.fetch(key.to_s, key.to_s)] = primitive(value) }
    renames = record[:metric] == REQUEST_METRIC ? HTTP_RENAMES : {}
    # payload는 호출부가 넣는 값이라 request_id·client.address 같은 기준 필드를 덮지 못하게 한다.
    # 충돌은 이름을 바꾼 뒤의 키로 검사한다.
    record[:payload]&.each do |key, value|
      key = renames.fetch(key, key)
      attrs[attrs.key?(key) ? "payload.#{key}" : key] = value
    end
    attrs.merge!(exception_attributes(record[:exception]).compact) if record[:exception]
    attrs
  end

  # OTel attribute가 받는 원시 타입은 그대로 두어 attributes_number/bool 맵에 들어가게 한다.
  # Numeric 전체가 아니라 Integer·Float만이다. BigDecimal 등은 OTLP에서 빈 값으로 인코딩된다.
  # @rbs value: untyped
  # @rbs return: String | Integer | Float | bool
  def primitive(value)
    case value
    when String, Integer, Float, true, false then value
    else value.to_s
    end
  end

  # @rbs exception: Hash[Symbol, untyped]
  # @rbs return: Hash[String, String?]
  def exception_attributes(exception)
    cause = exception[:cause]
    {
      "exception.type" => exception[:name],
      "exception.message" => exception[:message],
      "exception.stacktrace" => exception[:stack_trace]&.join("\n"),
      "exception.cause" => cause && "#{cause[:name]}: #{cause[:message]}"
    }
  end
end
