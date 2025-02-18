class LoopsUpdateFieldJob < ApplicationJob
  def perform(email, loops_field_name, loops_field_value)
    found_contact = LoopsSdk::Contacts.find(email: email)
    sleep 0.5

    if found_contact.empty?
      created_contact = LoopsSdk::Contacts.create(
        email: email,
        properties: {
          userGroup: 'Hack Clubber',
          source: "Airtable <> Loops Integrator - #{loops_field_name}"
        }
      )
      sleep 0.5
    end

    to_update = {}
    to_update[loops_field_name] = loops_field_value

    LoopsSdk::Contacts.update(
      email: email,
      properties: to_update
    )
    sleep 0.5

    Rails.logger.info "Updated #{email} with #{loops_field_name} to #{loops_field_value}"
  end
end
