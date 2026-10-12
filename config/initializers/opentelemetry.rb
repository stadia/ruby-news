# config/initializers/opentelemetry.rb
# rbs_inline: enabled

if Rails.env.production?
  require "opentelemetry/sdk"
  require "opentelemetry-exporter-otlp"
  require "opentelemetry-logs-sdk"
  require "opentelemetry-exporter-otlp-logs"

  # Shared resource for every signal (traces + logs) so SigNoz sees consistent
  # service / environment / version attributes and can filter across them.
  # `service.version` comes from the git SHA baked in as APP_REVISION (Dockerfile).
  otel_resource = OpenTelemetry::SDK::Resources::Resource.create(
    {
      "service.name" => "ruby-news",
      "deployment.environment" => Rails.env.to_s,
      "service.version" => ENV["APP_REVISION"]
    }.compact
  )

  OpenTelemetry::SDK.configure do |c|
    c.resource = otel_resource
    # use_all auto-enables every instrumentation gem loaded at boot via
    # Bundler.require (aws_sdk, concurrent_ruby, faraday, grpc, net_http, pg,
    # rack, rails + its sub-instrumentations, rake, ruby_llm). No manual
    # `require` needed — each gem self-registers into the instrumentation
    # registry on load, and use_all installs everything registered.
    #
    # RubyLLM is disabled until opentelemetry-instrumentation-ruby_llm supports
    # ruby_llm 2.0 (thoughtbot/opentelemetry-instrumentation-ruby_llm#39). 0.7.1
    # prepends Chat#complete and calls Message#model_id/#input_tokens, which 2.0
    # removed, so every chat in production would raise NoMethodError.
    c.use_all("OpenTelemetry::Instrumentation::RubyLLM" => { enabled: false })
  end

  # --- Logs: send structured records to SigNoz over OTLP ---
  # rails_semantic_logger still writes JSON to $stdout (see production.rb) for
  # `kubectl logs`. OtelLogAppender (lib/otel_log_appender.rb) additionally
  # emits OTLP LogRecords with body = message and everything else (logger name,
  # named tags, payload, duration, exception) as typed `attributes`, so SigNoz
  # can index/filter fields instead of tokenizing them inside `body`.
  #
  # Endpoint/headers come from the standard OTEL_EXPORTER_OTLP_* env vars
  # (falls back to OTEL_EXPORTER_OTLP_LOGS_ENDPOINT), same as traces.
  logger_provider = OpenTelemetry::SDK::Logs::LoggerProvider.new(resource: otel_resource)
  logger_provider.add_log_record_processor(
    OpenTelemetry::SDK::Logs::Export::BatchLogRecordProcessor.new(
      OpenTelemetry::Exporter::OTLP::Logs::LogsExporter.new
    )
  )
  OpenTelemetry.logger_provider = logger_provider

  # Must run AFTER logger_provider is set: the appender captures the provider
  # at construction time. metrics:false — no meter pipeline is configured.
  # after_initialize: the main autoloader (lib/ via autoload_lib) is set up
  # after config/initializers run, so OtelLogAppender cannot be referenced here.
  Rails.application.config.after_initialize do
    SemanticLogger.add_appender(appender: OtelLogAppender.new(metrics: false))
  end

  # at_exit runs in reverse order, so this runs before semantic_logger's own
  # flush. Drain its queue first, or the last logs hit a stopped provider.
  at_exit do
    SemanticLogger.flush
    logger_provider.shutdown
  end
end
