class WebhookPayloadHandlerJob < ApplicationJob
  LOOPS_FIELD_REGEX = /^Loops - (?<loops_field_name>.+)$/

  class MissingEmailFieldError < StandardError
    def initialize(table_id)
      super("Table #{table_id} must have a field titled 'Email'")
    end
  end

  class InvalidEmailFormatError < StandardError
    def initialize(email)
      super("Invalid email format for \"#{email}\"")
    end
  end

  retry_on AirtableService::RateLimitError, AirtableService::TimeoutError, wait: :polynomially_longer, attempts: Float::INFINITY

  def perform(payload)
    base_id = payload.base_id
    pbody = payload.body
    timestamp = Time.parse(payload.body['timestamp'])

    success = false

    ## determine changes, clear schema cache if neededd ##

    # hash in format { tableId => { recordId => { fieldId => 'newValue' } } }
    changes = {}
    # hash of full record values for records with changes
    # in format { tableId => { recordId => { fieldId => value} }
    fieldValues = {}

    pbody["changedTablesById"].each do |table_id, table_data|
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
    if pbody["createdTablesById"] || pbody["destroyedTableIds"]
      AirtableService::Bases.clear_schema_cache(base_id)
    end

    ## check field names ##

    schema = AirtableService::Bases.get_cached_schema(base_id: base_id)

    changes.each do |table_id, records|
      fields = schema[table_id]['fields']

      records.each do |record_id, field_values|
        loops_field_updates = {}
        email_value = nil

        field_values.each do |field_id, value|
          field = fields.find { |f| f['id'] == field_id }
          next unless field

          # if the webhook indicates that a field's value has changed that
          # matches our regex to detect fields to set in loops, queue a loops
          # update job
          match = field["name"].match(LOOPS_FIELD_REGEX)
          next unless match

          email_field = fields.find { |f| f['name'].downcase == 'email' }
          raise MissingEmailFieldError.new(table_id) unless email_field

          email_value = fieldValues[table_id][record_id][email_field['id']]
          raise InvalidEmailFormatError.new(email_value) unless EmailValidator.valid?(email_value, mode: :strict)

          loops_field_name = match[:loops_field_name]

          loops_field_updates[loops_field_name] = value
        end

        if loops_field_updates.any?
          # we set the priority to the timestamp of the webhook (lower numbesr are processed first)
          # this is to ensure that if we build up a queue, the oldest field
          # updates are processed first so the newest field changes are the last
          # to reflect
          LoopsUpdateFieldJob.set(priority: timestamp.to_i).perform_later(base_id, email_value, loops_field_updates)
        end
      end
    end

    success = true

  rescue MissingEmailFieldError, InvalidEmailFormatError => e
    Rails.logger.error e.message
    success = true
  ensure
    # destroy the payload after processing
    payload.destroy! if success
  end
end
