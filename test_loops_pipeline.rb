#!/usr/bin/env ruby
# Test script to simulate Airtable change and verify pipeline
# Run with: rails runner test_loops_pipeline.rb

# Test parameters
TEST_EMAIL = "zach+loopsapitest2@hackclub.com"
TEST_FIELD_NAME = "Loops - tmpZachLoopsApiTest"
TEST_VALUE = "hi"
TEST_SYNC_SOURCE_ID = ENV.fetch("TEST_SYNC_SOURCE_ID", nil)
TEST_TABLE_ID = "tblTest123"
TEST_RECORD_ID = "recTest456"

puts "=" * 80
puts "Testing Loops Integration Pipeline"
puts "=" * 80
puts "Email: #{TEST_EMAIL}"
puts "Field: #{TEST_FIELD_NAME}"
puts "Value: #{TEST_VALUE}"
puts ""

# Find or create sync source
if TEST_SYNC_SOURCE_ID
  sync_source = SyncSource.find_by(id: TEST_SYNC_SOURCE_ID)
  unless sync_source
    puts "ERROR: Sync source #{TEST_SYNC_SOURCE_ID} not found"
    exit 1
  end
else
  # Create a test sync source
  sync_source = SyncSource.find_or_create_by!(
    source: "airtable",
    source_id: "appTest123"
  ) do |ss|
    ss.poll_interval_seconds = 30
  end
  puts "Using sync source: #{sync_source.id} (#{sync_source.source_id})"
end

# Simulate field change detection
field_id = "fldTest789"
field_id_key = "#{field_id}/#{TEST_FIELD_NAME}"
row_id = "#{TEST_TABLE_ID}/#{TEST_RECORD_ID}"

puts "\nStep 1: Simulating Airtable change detection..."
puts "  Field ID: #{field_id_key}"
puts "  Row ID: #{row_id}"

# Detect change and get old_value from result
result = FieldValueBaseline.detect_change(
  sync_source: sync_source,
  row_id: row_id,
  field_id: field_id_key,
  current_value: TEST_VALUE
)
old_value = result[:old_value]
puts "  Old value: #{old_value.inspect}"

# Build changed_fields hash (as if from detect_changes)
# Note: This simulates what detect_changes would return
changed_fields = {
  field_id_key => {
    "value" => TEST_VALUE,
    "old_value" => old_value,
    "modified_at" => Time.current.iso8601
  }
}

puts "\nStep 2: Enqueuing PrepareLoopsFieldsForOutboxJob..."
puts "  Changed fields: #{changed_fields.keys.join(', ')}"

job_id = PrepareLoopsFieldsForOutboxJob.perform_async(
  TEST_EMAIL,
  sync_source.id,
  TEST_TABLE_ID,
  TEST_RECORD_ID,
  changed_fields
)

puts "  Job ID: #{job_id}"

# Process the job immediately (for testing)
puts "\nStep 3: Processing PrepareLoopsFieldsForOutboxJob..."
begin
  PrepareLoopsFieldsForOutboxJob.new.perform(
    TEST_EMAIL,
    sync_source.id,
    TEST_TABLE_ID,
    TEST_RECORD_ID,
    changed_fields
  )
  puts "  ✓ Job completed successfully"
rescue => e
  puts "  ✗ Job failed: #{e.class} - #{e.message}"
  puts "  #{e.backtrace.first(5).join("\n  ")}"
  exit 1
end

# Check outbox envelope
envelope = LoopsOutboxEnvelope.where(email_normalized: EmailNormalizer.normalize(TEST_EMAIL)).last
if envelope
  puts "\nStep 4: Outbox envelope created"
  puts "  Status: #{envelope.status}"
  puts "  Payload keys: #{envelope.payload.keys.join(', ')}"
  puts "  Field value: #{envelope.payload.dig('tmpZachLoopsApiTest', 'value')}"
else
  puts "\nStep 4: ✗ No outbox envelope found!"
  exit 1
end

# Process dispatch worker
puts "\nStep 5: Processing LoopsDispatchWorker..."
begin
  LoopsDispatchWorker.new.perform
  puts "  ✓ Dispatch worker completed"
rescue => e
  puts "  ✗ Dispatch worker failed: #{e.class} - #{e.message}"
  puts "  #{e.backtrace.first(5).join("\n  ")}"
  exit 1
end

# Wait a moment for processing
sleep 2

# Check envelope status
envelope.reload
puts "\nStep 6: Envelope status after dispatch"
puts "  Status: #{envelope.status}"

# Check audit records
audits = LoopsContactChangeAudit.where(email_normalized: EmailNormalizer.normalize(TEST_EMAIL))
puts "  Audit records created: #{audits.count}"

# Verify via Loops API
puts "\nStep 7: Verifying via Loops API..."
begin
  contact = LoopsService.find_contact(email: TEST_EMAIL)

  if contact.is_a?(Array) && contact.any?
    contact_data = contact.first
    puts "  ✓ Contact found in Loops"
    puts "  Contact ID: #{contact_data['id']}"

    field_value = contact_data['tmpZachLoopsApiTest']
    puts "  Field value in Loops: #{field_value.inspect}"

    if field_value == TEST_VALUE
      puts "\n" + "=" * 80
      puts "SUCCESS! Value propagated correctly to Loops API"
      puts "=" * 80
    else
      puts "\n" + "=" * 80
      puts "WARNING: Value mismatch"
      puts "  Expected: #{TEST_VALUE.inspect}"
      puts "  Got: #{field_value.inspect}"
      puts "=" * 80
    end
  else
    puts "  ⚠ Contact not found in Loops (may need to be created first)"
    puts "  Response: #{contact.inspect}"
  end
rescue => e
  puts "  ✗ Loops API error: #{e.class} - #{e.message}"
  puts "  #{e.backtrace.first(3).join("\n  ")}"
end

puts "\nDone!"
