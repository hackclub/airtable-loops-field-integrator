require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module App
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Don't generate system test files.
    config.generators.system_tests = nil

    # Use GoodJob as the queue adapter
    config.active_job.queue_adapter = :good_job
    config.good_job.preserve_job_records = false
    config.good_job.enable_cron = true
    config.good_job.cron_graceful_restart_period = 1.minute
    config.good_job.cron = {
      daily_webhook_refresh: {
        cron: "0 9 * * *",
        class: "CronDailyWebhookRefreshAllJob",
        description: "Refresh all webhooks daily"
      },
      webhook_polling_setup: {
        cron: "* * * * *",
        class: "WebhookPollingSetupJob",
        description: "Setup webhooks for any missing bases every minute",
        enabled_by_default: -> { Rails.env.production? } # Only enable in production, otherwise can be enabled manually through Dashboard
      }
    }
  end
end
