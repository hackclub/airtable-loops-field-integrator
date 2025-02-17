class WebhookPollingSetupJob < ApplicationJob
  include GoodJob::ActiveJobExtensions::Concurrency

  good_job_control_concurrency_with(
    total_limit: 1,
    perform_limit: 1
  )

  def perform(base_ids: nil)
    AirtableService::Bases.find_each do |base|
      next if base_ids.present? && !base_ids.include?(base['id'])
      next if Webhook.unexpired.for_base(base['id']).exists?

      Rails.logger.info "Setting up webhook for base: #{base['name']}"

      Webhook.create!(
        base_id: base['id'],
        notification_url: "#{ENV.fetch('WEBHOOK_BASE_URL')}/airtable/webhook",
        specification: {
          options: {
            filters: {
              dataTypes: [ 'tableData', 'tableFields', 'tableMetadata' ]
            },
            includes: {
              includeCellValuesInFieldIds: 'all'
            }
          }
        }
      )
    end
  end
end