# config/initializers/ruby_llm.rb or similar
RubyLLM.configure do |config|
  # --- Default Models ---
  # Used by RubyLLM.chat, RubyLLM.embed, RubyLLM.paint if no model is specified.
  config.default_model = "gemini-3.6-flash"
  # config.gemini_api_base = 'https://generativelanguage.googleapis.com/v1'

  # --- Connection Settings ---
  config.request_timeout = 120  # Request timeout in seconds (default: 120)
  config.max_retries = 3        # Max retries on transient network errors (default: 3)
  config.retry_interval = 0.2 # Initial delay in seconds (default: 0.1)

  config.model_registry_file = "config/models.json"

  # --- OR Custom Logger ---
  config.logger = Rails.logger

  config.gemini_api_key = ENV.fetch("GEMINI_API_KEY", nil)

  # API key - use what your server expects
  config.openai_api_key = ENV.fetch("OPENAI_API_KEY", nil)

  config.openrouter_api_key = ENV.fetch("OPENROUTER_API_KEY", nil)

  config.ollama_cloud_api_key = ENV.fetch("OLLAMA_CLOUD_API_KEY", nil)
end
