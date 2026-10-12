# rbs_inline: enabled

require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module RubyNews
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks protobuf])

    # app/skills holds standalone CLI scripts and reference material for the
    # humanize_korean skill, not autoloadable constants. Rails treats every
    # app/* subdirectory as an autoload root, so Zeitwerk must be told to skip
    # it or eager loading raises NameError on boot.
    Rails.autoloaders.main.ignore(Rails.root.join("app/skills"))

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.

    config.time_zone = "Asia/Seoul"
    # config.eager_load_paths << Rails.root.join("extras")

    config.i18n.available_locales = %w[en ko ja]
    config.i18n.default_locale = :ko

    config.mission_control.jobs.base_controller_class = "Madmin::ApplicationController"
    config.mission_control.jobs.http_basic_auth_enabled = false

    # Cache query log tags for better performance
    config.active_record.cache_query_log_tags = true

    # Enable query log tags around perform for better debugging
    config.active_job.log_query_tags_around_perform = true

    # Started/Processing/Rendered 줄은 요청당 레코드를 4~5개로 불리지만 정보는 Completed 한 줄과
    # 트레이스 span에 이미 있다(SigNoz 실측: 하루 3.7만 건 중 약 40%).
    config.rails_semantic_logger.started = false
    config.rails_semantic_logger.processing = false
    config.rails_semantic_logger.rendered = false
    config.rails_semantic_logger.quiet_assets = true
    config.colorize_logging = false
    config.rails_semantic_logger.format = :json
  end
end
