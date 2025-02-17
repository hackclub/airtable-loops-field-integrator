# Every day, refresh every Webhook that is not expired to keep them active.
class CronDailyWebhookRefreshAllJob < ApplicationJob
  def perform
    batch = GoodJob::Batch.new(
      description: "Daily webhook refresh for #{Time.current.to_date}"
    )

    batch.add do
      Webhook.unexpired.find_each do |webhook|
        WebhookRefreshJob.perform_later(webhook)
      end
    end

    batch.enqueue
    Rails.logger.info "Enqueued webhook refresh batch with #{batch.active_jobs.size} jobs"
  end
end 