source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.3"
# ActiveSupport 8.1.3.1 passes JSON.parse options positionally; json 3 accepts
# keyword options only. Keep the compatible API until Rails updates its decoder.
gem "json", "< 4"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.6"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"
# Use Tailwind CSS [https://github.com/rails/tailwindcss-rails]
gem "tailwindcss-rails", "~> 4.5"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"

# Authentication [https://github.com/heartcombo/devise]
gem "devise", "~> 5.0"
gem "devise-i18n"
gem "devise-jwt", "~> 0.12"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cable"
gem "solid_cache"
gem "solid_queue"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
# gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
# gem "thruster", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
gem "aws-sdk-s3", require: false
gem "image_processing", "~> 2.0"
gem "ruby-vips", "~> 2.0" # if using libvips

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # RSpec for API specs (used alongside minitest)
  gem "rspec-rails", "~> 8.0"
  gem "rswag-specs", "~> 2.16"

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Patch-level verification for Bundler [https://github.com/rubysec/bundler-audit]
  gem "bundler-audit", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "dotenv-rails"
  gem "faker"
  gem "i18n-tasks", "~> 1.1.2"
  gem "minitest", "~> 6.0"
  gem "minitest-mock"
  gem "rubocop", require: false
  gem "rubocop-i18n", require: false
  gem "rubocop-minitest", require: false
  gem "rubocop-rails-omakase", require: false
  gem "rubocop-rbs_inline", require: false
  gem "rubocop-sorbet", require: false

  # Quality gates
  gem "flog", require: false
  gem "simplecov", require: false
  gem "tapioca", require: false

  # Test profiling [https://github.com/test-prof/test-prof]
  # 계측은 ENV 변수로만 켜진다. 평소 실행에는 아무 영향이 없다.
  gem "test-prof", "~> 1.6"
  gem "vernier", require: false # TEST_VERNIER=1 일 때만 로드되는 샘플링 프로파일러
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "letter_opener"
  gem "ruby-lsp", "~> 0.27.0.beta5"
  gem "ruby-lsp-brakeman", require: false
  gem "ruby_ui", "~> 1.2"
  gem "sorbet"
  gem "web-console"
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  gem "climate_control"
  gem "selenium-webdriver"
end

gem "google-protobuf", require: false
gem "pagy", "~> 43.6" # omit patch digit
gem "sorbet-runtime"
# silence Ruby 3.4 warnings
gem "acts-as-taggable-on"
gem "awesome_nested_set"
gem "discard"
gem "hairtrigger"
gem "inkmark"
gem "madmin", "~> 2.4"
gem "meta-tags"
gem "mission_control-jobs"
gem "neighbor"
gem "oauth2", "~> 2.0"
gem "omniauth-apple"
gem "omniauth-github"
gem "omniauth-google-oauth2"
gem "omniauth-rails_csrf_protection"
gem "ostruct"
gem "pg_search"
gem "rails-i18n"
gem "rss"
gem "ruby-readability"
gem "schema_dot_org"
gem "sitemap_generator"
gem "yt"
# Use sqlite3 as the database for Active Record
gem "dry-operation"
gem "sqlite3", ">= 2.1"
gem "youtube-transcript-rb", "~> 0.2.0"

gem "amazing_print"
gem "fedipub", github: "stadia/federails"
# gem "fedipub", path: "../federails"
gem "deepl-rb", require: "deepl"
gem "friendly_id"
gem "lexxy", "~> 0.9.24"
gem "oj"
gem "pg_query"
gem "phlex-icons"
gem "phlex-rails", "~> 2.4"
gem "prosopite"
gem "rack-cors"

gem "rails_semantic_logger"
gem "reactionview", "~> 0.4.0"
# OpenAPI/Swagger documentation
gem "discordrb-webhooks"
gem "resend"
gem "rswag-api", "~> 2.16"
gem "rswag-ui", "~> 2.16"
gem "ruby-mcp-client", "~> 2.0"
gem "slack-ruby-client", "~> 3.2.0"
gem "tailwind_merge", "~> 1.5"
gem "web-push", "~> 3.1"

gem "honeybadger"
gem "newrelic_rpm"
gem "opentelemetry-exporter-otlp"
gem "opentelemetry-exporter-otlp-logs"
gem "opentelemetry-logs-sdk"
gem "opentelemetry-sdk"
gem "sentry-rails"
gem "sentry-ruby"
# gem "opentelemetry-instrumentation-all"
gem "opentelemetry-instrumentation-aws_sdk"
gem "opentelemetry-instrumentation-concurrent_ruby"
gem "opentelemetry-instrumentation-faraday"
gem "opentelemetry-instrumentation-grpc"
gem "opentelemetry-instrumentation-net_http"
gem "opentelemetry-instrumentation-pg"
gem "opentelemetry-instrumentation-rack"
gem "opentelemetry-instrumentation-rails"
gem "opentelemetry-instrumentation-rake"
gem "opentelemetry-instrumentation-ruby_llm"

gem "ruby_llm", "~> 1.16"
gem "ruby_llm-monitoring"
# OpenAI Responses API 프로바이더. ruby_llm 2.0이 릴리스되면 코어로 흡수되므로 제거한다.
# gpt-5.x는 chat/completions에서 function tool + reasoning을 함께 쓸 수 없다 (crmne/ruby_llm#213).
gem "ruby_llm-responses_api"
gem "ruby_llm-schema"
gem "ruby_llm-skills"
