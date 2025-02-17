class WebhookNotificationHandler < ApplicationJob
  include GoodJob::ActiveJobExtensions::Concurrency

  good_job_control_concurrency_with(
    perform_throttle: [1, 1.second],
    key: -> { "airtable_api/#{arguments.first}"}
  )

  def perform(base_id, webhook_id, timestamp)
    w = Webhook.find_by(id: webhook_id)
    if w.nil?
      Rails.logger.error "Webhook not found for base #{base_id}, webhook #{webhook_id} at #{timestamp}"
      return
    end

    if w.base_id != base_id
      Rails.logger.error "Webhook base ID mismatch for base #{base_id}, webhook #{webhook_id} at #{timestamp}"
      return
    end

    Rails.logger.info "Received webhook notification for base #{base_id}, webhook #{webhook_id} at #{timestamp}"

    w.find_each_new_payload do |payload|
      WebhookPayloadHandlerJob.perform_later(base_id, payload)
    end
  end
end
