class WebhookPollingSetupJob < ApplicationJob
  def perform
    AirtableService::Bases.find_each do |base|
      puts "Setting up webhook for base: #{base['name']}"
    end
  end
end