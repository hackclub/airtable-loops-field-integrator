# Ensure ruby_llm/schema is loaded for Sidekiq workers
require "ruby_llm/schema"

RubyLLM.configure do |config|
  config.openai_api_key = ENV['OPENAI_API_KEY']
  config.default_model = ENV.fetch('LLM_MODEL', 'gpt-5-mini')
end
