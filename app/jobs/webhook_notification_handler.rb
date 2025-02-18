class WebhookNotificationHandler < ApplicationJob
  retry_on AirtableService::RateLimitError, wait: :polynomially_longer, attempts: Float::INFINITY

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
      p = Payload.create!(
        base_id: base_id,
        webhook_id: webhook_id,
        body: payload
      )
      WebhookPayloadHandlerJob.perform_later(p)
    end
end
