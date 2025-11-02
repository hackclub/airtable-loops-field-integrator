require_relative "../lib/email_normalizer"

class PrepareLoopsFieldsForOutboxJob
  include Sidekiq::Worker

  sidekiq_options queue: :default

  # OUTPUT ENVELOPE FORMAT
  # ======================
  #
  # The output envelope is a Hash where:
  # - Keys are Loops field names (strings)
  # - Values are field metadata hashes with the following structure:
  #
  #   {
  #     "loops_field_name" => {
  #       value: <any>,           # The actual value to send to Loops (required)
  #       strategy: :upsert,      # Field update strategy: :upsert or :override (required)
  #       modified_at: "2025-11-02T21:00:00Z"  # ISO8601 timestamp (required)
  #     }
  #   }
  #
  # Example:
  #   {
  #     "tmpZachLoopsApiTest" => {
  #       value: "hi",
  #       strategy: :upsert,
  #       modified_at: "2025-11-02T21:00:00Z"
  #     }
  #   }
  #
  # Strategy meanings:
  # - :upsert: Only update if value is not nil (skip nil values)
  # - :override: Always update, even if value is nil
  #
  # Field name mapping:
  # - Sync source field names (e.g., "Loops - tmpZachLoopsApiTest") should be mapped
  #   to Loops field names (e.g., "tmpZachLoopsApiTest") by stripping prefixes
  # - This mapping logic will be implemented later

  def perform(email, sync_source_id, table_id, record_id, changed_fields)
    # ALWAYS use test values regardless of input parameters
    # This ensures any Airtable row edit triggers the same test envelope
    #
    # changed_fields format:
    # {
    #   "field_id/field_name" => {
    #     "value" => <current_value>,
    #     "old_value" => <previous_value> or nil,
    #     "modified_at" => "ISO8601 timestamp"
    #   }
    # }
    
    # Test values (hardcoded):
    test_email = EmailNormalizer.normalize(email)
    test_field_name = "Loops - tmpZachLoopsApiTest"
    # changed fields is {"fldMXhauv0JDKMq6h/Loops - tmpZachLoopsApiTest"=>{"value"=>"hi12", "old_value"=>"hi123", "modified_at"=>"2025-11-02T21:44:14Z"}}
    # set test_value to the value of the changed_fields
    test_field_data = changed_fields["fldMXhauv0JDKMq6h/Loops - tmpZachLoopsApiTest"]
    test_value = test_field_data["value"]
    test_field_id = "fldTest789"
    
    # Normalize test email
    email_normalized = EmailNormalizer.normalize(test_email)
    return unless email_normalized

    # Create output envelope with test values (ignore input parameters)
    envelope = build_test_envelope_with_fixed_values(test_field_id, test_field_name, test_value)

    # Build provenance with test values (use input sync_source_id for reference)
    provenance = build_test_provenance(sync_source_id, table_id, record_id, test_field_id, test_field_name, test_value)

    # Write to outbox
    LoopsOutboxEnvelope.create!(
      email_normalized: email_normalized,
      payload: envelope,
      status: :queued,
      provenance: provenance,
      sync_source_id: sync_source_id
    )
  end

  private

  # Build test envelope with fixed test values (ignores input parameters)
  def build_test_envelope_with_fixed_values(field_id, field_name, value)
    # Map field name: strip "Loops - " prefix
    loops_field_name = field_name.sub(/\ALoops\s*-\s*/i, "")
    
    # Build envelope entry according to the documented format with test values
    {
      loops_field_name => {
        value: value,
        strategy: :upsert,
        modified_at: Time.current.iso8601
      }
    }
  end

  # Build test provenance with fixed test values (uses input sync_source_id for reference)
  def build_test_provenance(sync_source_id, table_id, record_id, field_id, field_name, value)
    sync_source = SyncSource.find_by(id: sync_source_id)
    sync_source_type = sync_source&.source || "unknown"
    
    # Build field provenance with test values
    fields_array = [{
      sync_source_field_id: field_id,
      sync_source_field_name: field_name,
      former_sync_source_value: nil,  # Always nil for test
      new_sync_source_value: value,
      modified_at: Time.current.iso8601
    }]

    provenance = {
      sync_source_id: sync_source_id,
      sync_source_type: sync_source_type,
      sync_source_table_id: table_id,
      sync_source_record_id: record_id,
      fields: fields_array,
      created_from: "#{sync_source_type}_poller"
    }
    
    if sync_source
      provenance[:sync_source_metadata] = {
        source_id: sync_source.source_id
      }.merge(sync_source.metadata || {})
    end
    
    provenance
  end
end

