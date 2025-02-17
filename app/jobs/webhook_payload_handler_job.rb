class WebhookPayloadHandlerJob < ApplicationJob
  LOOPS_FIELD_REGEX = /^Loops - (?<loops_field_name>.+)$/

  def perform(base_id, payload)
    ## determine changes, clear schema cache if neededd ##

    # hash in format { tableId => { recordId => { fieldId => 'newValue' } } }
    changes = {}
    # hash of full record values for records with changes
    # in format { tableId => { recordId => { fieldId => value} }
    fieldValues = {}

    payload["changedTablesById"].each do |table_id, table_data|
      changes[table_id] = {}
      fieldValues[table_id] = {}

      # Handle changed records
      if table_data["changedRecordsById"]
        table_data["changedRecordsById"].each do |record_id, record_data|
          # Get the current (changed) values
          current_values = record_data["current"]["cellValuesByFieldId"]
          changes[table_id][record_id] = current_values

          # Store all field values
          fieldValues[table_id][record_id] = record_data.dig("current", "cellValuesByFieldId") || {}
          fieldValues[table_id][record_id].merge!(record_data.dig("unchanged", "cellValuesByFieldId") || {})
        end
      end

      # Handle created records
      if table_data["createdRecordsById"] 
        table_data["createdRecordsById"].each do |record_id, record_data|
          # Get the cell values
          cell_values = record_data["cellValuesByFieldId"]
          changes[table_id][record_id] = cell_values

          # Store all field values
          fieldValues[table_id][record_id] = cell_values
        end
      end

      # invalidate cache for field changes
      if table_data["createdFieldsById"] || table_data["changedFieldsById"] || table_data["destroyedFieldIds"]
        AirtableService::Bases.clear_schema_cache(base_id)
      end
    end

    # invalidate cache for table changes
    if payload["createdTablesById"] || payload["destroyedTableIds"]
      AirtableService::Bases.clear_schema_cache(base_id)
    end

    ## check field names ##

    schema = AirtableService::Bases.get_cached_schema(base_id: base_id)

    changes.each do |table_id, records|
      fields = schema[table_id]['fields']

      email_field = fields.find { |f| f['name'].downcase == 'email' }
      raise "There must be a field titled 'Email'" unless email_field

      records.each do |record_id, field_values|
        email_value = fieldValues[table_id][record_id][email_field['id']]
        raise "Invalid email format for \"#{email}\"" unless EmailValidator.valid?(email, mode: :strict)

        field_values.each do |field_id, value|
          field = fields.find { |f| f['id'] == field_id }

          # if the webhook indicates that a field's value has changed that
          # matches our regex to detect fields to set in loops, queue a loops
          # update job
          match = field["name"].match(LOOPS_FIELD_REGEX)
          next unless match

          loops_field_name = match[:loops_field_name]

          LoopsUpdateFieldJob.perform_later(email, loops_field_name, value)
        end
      end
    end
  end
end
