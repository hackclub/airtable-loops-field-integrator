class LoopsUpdateFieldJob < ApplicationJob
  def perform(email, loops_field_name, loops_field_value)
    found_contact = LoopsSdk::Contacts.find(email: email)

    if found_contact.empty?
      created_contact = LoopsSdk::Contacts.create(
        email: email,
        properties: {
          userGroup: 'Hack Clubber',
          source: "Airtable <> Loops Integrator - #{loops_field_name}"
        }
      )
    end

    to_update = {}
    to_update[loops_field_name] = loops_field_value

    LoopsSdk::Contacts.update(
      email: email,
      properties: to_update
    )

    Rails.logger.info "Updated #{email} with #{loops_field_name} to #{loops_field_value}"
  end
end
