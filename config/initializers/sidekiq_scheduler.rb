if ENV["SIDEKIQ_SCHEDULER"] == "1"
  require "sidekiq-scheduler"

  Sidekiq.configure_server do |config|
    # Load schedule from config/sidekiq.yml
    config.on(:startup) do
      Sidekiq.schedule = YAML.load_file(Rails.root.join("config", "sidekiq.yml"))[:schedule] || {}
      Sidekiq::Scheduler.reload_schedule!
    end
  end
end
