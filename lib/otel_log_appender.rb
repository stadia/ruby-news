# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

require "semantic_logger/appender/open_telemetry"

# SigNoz(ClickHouse logs_v2)에서 검색과 인덱스가 먹히는 모양으로 LogRecord를 보낸다.
# 기본 appender는 message·name·named_tags·duration·exception을 JSON Hash째 body에 넣는데,
# body는 String 컬럼이라 그 필드들은 body 토큰 인덱스의 노이즈가 되고 맵 인덱스를 못 탄다.
# body에는 message만 두고, 나머지는 typed attributes(attributes_string/number 맵)로 평탄화한다.
# host·pid·application·environment는 resource와 중복이라 버린다.
class OtelLogAppender < SemanticLogger::Appender::OpenTelemetry
  # 트레이스 span과 같은 OTel semconv 키로 맞춘다.
  RENAMES = {
    "method" => "http.request.method",
    "path" => "url.path",
    "status" => "http.response.status_code",
    "ip" => "client.address"
  }.freeze

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
      "tags" => record[:tags]&.map(&:to_s)
    }
    record[:named_tags]&.each { |key, value| attrs[key.to_s] = primitive(value) }
    # payload는 호출부가 넣는 값이라 request_id·code.namespace 같은 기준 필드를 덮지 못하게 한다.
    record[:payload]&.each { |key, value| attrs[attrs.key?(key) ? "payload.#{key}" : key] = value }
    attrs.merge!(exception_attributes(record[:exception])) if record[:exception]
    attrs.compact.transform_keys { |key| RENAMES.fetch(key, key) }
  end

  # OTel attribute가 받는 원시 타입은 그대로 두어 attributes_number/bool 맵에 들어가게 한다.
  # @rbs value: untyped
  # @rbs return: String | Numeric | bool
  def primitive(value)
    case value
    when String, Numeric, true, false then value
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
