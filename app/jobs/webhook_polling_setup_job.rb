class WebhookPollingSetupJob < ApplicationJob
  def perform(base_ids: nil)
    AirtableService::Bases.find_each do |base|
      next if base_ids.present? && !base_ids.include?(base['id'])
      next if Webhook.unexpired.for_base(base['id']).exists?

      Rails.logger.info "Setting up webhook for base: #{base['name']}"

      Webhook.create!(
        base_id: base['id'],
        notification_url: 'https://c77848ff3f80.ngrok.app/airtable/webhook',
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