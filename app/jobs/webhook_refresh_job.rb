# Refresh an individual Webhook to keep it active
class WebhookRefreshJob < ApplicationJob
  include GoodJob::ActiveJobExtensions::Concurrency

  good_job_control_concurrency_with(
    perform_throttle: [1, 1.second],
    key: -> { "airtable_api/#{arguments.first.base_id}"}
  )

  def perform(webhook)
    Rails.logger.info "Refreshing webhook #{webhook.id} for base #{webhook.base_id}"
    webhook.refresh!
  end
end