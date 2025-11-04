ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require "bundler/setup" # Set up gems listed in the Gemfile.

# Load .env file if it exists
if File.exist?(File.expand_path("../.env", __dir__))
  require "dotenv"
  Dotenv.load
end

require "bootsnap/setup" # Speed up boot time by caching expensive operations.
