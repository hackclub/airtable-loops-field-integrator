# Refresh an individual Webhook to keep it active
class WebhookRefreshJob < ApplicationJob
  def perform(webhook)
    Rails.logger.info "Refreshing webhook #{webhook.id} for base #{webhook.base_id}"
    webhook.refresh!
  end
end