# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

class ApplicationJob < ActiveJob::Base
  # rescue_from은 나중에 선언한 핸들러가 먼저 매칭되므로, 아래 retry_on/discard_on이
  # 이 일반 핸들러보다 우선하도록 맨 앞에 둔다.
  rescue_from(StandardError) do |exception|
    # Log error details
    logger.error "Job failed: #{self.class.name} with arguments: #{arguments}"
    logger.error "Error: #{exception.class.name} - #{exception.message}"
    logger.error exception.backtrace.join("\n") if Rails.env.development?

    # Re-raise for proper job failure handling
    raise exception
  end

  # Automatically retry jobs that encountered a deadlock
  retry_on ActiveRecord::Deadlocked, wait: 5.seconds, attempts: 3

  # Retry on connection errors with backoff
  retry_on ActiveRecord::ConnectionNotEstablished, wait: :polynomially_longer, attempts: 5

  # Discard jobs for missing records
  discard_on ActiveJob::DeserializationError
  discard_on ActiveRecord::RecordNotFound

  # Provides default URL options for URL helpers in jobs.
  def default_url_options
    Rails.application.routes.default_url_options
  end
end
