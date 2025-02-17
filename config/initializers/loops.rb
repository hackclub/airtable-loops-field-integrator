require "loops_sdk"

LoopsSdk.configure do |config|
  config.api_key = Rails.application.credentials.loops_api_key
end
