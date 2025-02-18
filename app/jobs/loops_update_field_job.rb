class LoopsUpdateFieldJob < ApplicationJob
  include GoodJob::ActiveJobExtensions::Concurrency

  good_job_control_concurrency_with(
    perform_throttle: [2, 1.second],
    key: -> { 'loops_api' }
  )

  # loops_field_updates is a hash of field names and values to update
  # ex. { "firstName" => "John", "lastName" => "Doe" }
  def perform(base_id, email, loops_field_updates)
    found_contact = LoopsSdk::Contacts.find(email: email)

    if found_contact.empty?
      base = AirtableService::Bases.find_cached(base_id)

      created_contact = LoopsSdk::Contacts.create(
        email: email,
        properties: {
          userGroup: 'Hack Clubber',
          source: "Airtable - #{base['name']}"
        }
      )
    end

    LoopsSdk::Contacts.update(
      email: email,
      properties: loops_field_updates
    )

    Rails.logger.info "Updated #{email} with fields: #{loops_field_updates.inspect}"
  end
end
