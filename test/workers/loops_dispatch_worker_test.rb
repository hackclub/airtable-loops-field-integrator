require "test_helper"

class LoopsDispatchWorkerTest < ActiveSupport::TestCase
  # Disable parallelization for this test class since we're testing database interactions
  parallelize(workers: 1)

  # Disable transactional tests for this test class
  # Advisory locks are session-level, not transaction-level
  self.use_transactional_tests = false

  def setup
    @sync_source = SyncSource.create!(
      source: "airtable",
      source_id: "app123",
      poll_interval_seconds: 30
    )

    @email = "test@example.com"
    @email_normalized = EmailNormalizer.normalize(@email)

    # Clean up any existing data
    LoopsOutboxEnvelope.destroy_all
    LoopsFieldBaseline.destroy_all
    LoopsContactChangeAudit.destroy_all
  end

  def teardown
    # Clean up any lingering advisory locks
    cleanup_advisory_locks
    LoopsOutboxEnvelope.destroy_all
    LoopsFieldBaseline.destroy_all
    LoopsContactChangeAudit.destroy_all
    SyncSource.destroy_all
  end

  test "merges multiple envelopes for same email and sends latest value based on modified_at" do
    # Track what gets sent to Loops API
    sent_payload = nil

    # Mock LoopsService.update_contact to capture what's actually sent
    original_update_contact = LoopsService.method(:update_contact)
    LoopsService.define_singleton_method(:update_contact) do |email:, **kwargs|
      sent_payload = kwargs.dup
      { "success" => true, "id" => "test-request-123" }
    end

    begin
      # Create multiple envelopes for the same email with different values and timestamps
      # The one with the latest modified_at should win
      base_time = Time.parse("2025-11-02T10:00:00Z")

      envelope1 = LoopsOutboxEnvelope.create!(
        email_normalized: @email_normalized,
        payload: {
          "field1" => {
            "value" => "value1",
            "strategy" => "upsert",
            "modified_at" => base_time.iso8601
          }
        },
        status: :queued,
        provenance: build_test_provenance,
        sync_source_id: @sync_source.id
      )

      envelope2 = LoopsOutboxEnvelope.create!(
        email_normalized: @email_normalized,
        payload: {
          "field1" => {
            "value" => "value2",
            "strategy" => "upsert",
            "modified_at" => (base_time + 1.minute).iso8601
          }
        },
        status: :queued,
        provenance: build_test_provenance,
        sync_source_id: @sync_source.id
      )

      envelope3 = LoopsOutboxEnvelope.create!(
        email_normalized: @email_normalized,
        payload: {
          "field1" => {
            "value" => "value3",
            "strategy" => "upsert",
            "modified_at" => (base_time + 30.seconds).iso8601  # Earlier than envelope2
          }
        },
        status: :queued,
        provenance: build_test_provenance,
        sync_source_id: @sync_source.id
      )

      # Run the dispatch worker
      worker = LoopsDispatchWorker.new
      worker.perform

      # Verify all envelopes were processed
      assert_equal "sent", envelope1.reload.status, "Envelope1 should be marked as sent"
      assert_equal "sent", envelope2.reload.status, "Envelope2 should be marked as sent"
      assert_equal "sent", envelope3.reload.status, "Envelope3 should be marked as sent"

      # Verify the latest value (value2) was sent, not value1 or value3
      assert_not_nil sent_payload, "LoopsService.update_contact should have been called"
      assert_equal "value2", sent_payload["field1"],
        "Should send value2 (latest modified_at), but got #{sent_payload['field1']}"

      # Verify baseline was updated with the correct value
      baseline = LoopsFieldBaseline.find_by(
        email_normalized: @email_normalized,
        field_name: "field1"
      )
      assert_not_nil baseline, "Baseline should be created"
      assert_equal "value2", baseline.last_sent_value, "Baseline should have latest value"

    ensure
      # Restore original method
      LoopsService.define_singleton_method(:update_contact, original_update_contact)
    end
  end

  test "merges multiple fields from different envelopes" do
    # Track what gets sent to Loops API
    sent_payload = nil

    # Mock LoopsService.update_contact to capture what's actually sent
    original_update_contact = LoopsService.method(:update_contact)
    LoopsService.define_singleton_method(:update_contact) do |email:, **kwargs|
      sent_payload = kwargs.dup
      { "success" => true, "id" => "test-request-123" }
    end

    begin
      base_time = Time.parse("2025-11-02T10:00:00Z")

      # Envelope with field1
      envelope1 = LoopsOutboxEnvelope.create!(
        email_normalized: @email_normalized,
        payload: {
          "field1" => {
            "value" => "value1",
            "strategy" => "upsert",
            "modified_at" => base_time.iso8601
          }
        },
        status: :queued,
        provenance: build_test_provenance,
        sync_source_id: @sync_source.id
      )

      # Envelope with field2
      envelope2 = LoopsOutboxEnvelope.create!(
        email_normalized: @email_normalized,
        payload: {
          "field2" => {
            "value" => "value2",
            "strategy" => "upsert",
            "modified_at" => (base_time + 1.minute).iso8601
          }
        },
        status: :queued,
        provenance: build_test_provenance,
        sync_source_id: @sync_source.id
      )

      # Envelope with updated field1 (should win over envelope1)
      envelope3 = LoopsOutboxEnvelope.create!(
        email_normalized: @email_normalized,
        payload: {
          "field1" => {
            "value" => "value1_updated",
            "strategy" => "upsert",
            "modified_at" => (base_time + 2.minutes).iso8601
          }
        },
        status: :queued,
        provenance: build_test_provenance,
        sync_source_id: @sync_source.id
      )

      # Run the dispatch worker
      worker = LoopsDispatchWorker.new
      worker.perform

      # Verify all envelopes were processed
      assert_equal "sent", envelope1.reload.status
      assert_equal "sent", envelope2.reload.status
      assert_equal "sent", envelope3.reload.status

      # Verify both fields were sent with correct values
      assert_not_nil sent_payload, "LoopsService.update_contact should have been called"
      assert_equal "value1_updated", sent_payload["field1"],
        "field1 should have latest value (value1_updated)"
      assert_equal "value2", sent_payload["field2"],
        "field2 should have value2"
      assert_equal 2, sent_payload.keys.size,
        "Should send exactly 2 fields, but got #{sent_payload.keys.inspect}"

    ensure
      # Restore original method
      LoopsService.define_singleton_method(:update_contact, original_update_contact)
    end
  end

  test "handles string keys vs symbol keys in payload correctly" do
    # Track what gets sent to Loops API
    sent_payload = nil

    # Mock LoopsService.update_contact to capture what's actually sent
    original_update_contact = LoopsService.method(:update_contact)
    LoopsService.define_singleton_method(:update_contact) do |email:, **kwargs|
      sent_payload = kwargs.dup
      { "success" => true, "id" => "test-request-123" }
    end

    begin
      base_time = Time.parse("2025-11-02T10:00:00Z")

      # Envelope with string keys (as JSONB stores them)
      envelope1 = LoopsOutboxEnvelope.create!(
        email_normalized: @email_normalized,
        payload: {
          "field1" => {
            "value" => "value1",
            "strategy" => "upsert",
            "modified_at" => base_time.iso8601
          }
        },
        status: :queued,
        provenance: build_test_provenance,
        sync_source_id: @sync_source.id
      )

      # Envelope with symbol keys (to test merging handles both)
      envelope2 = LoopsOutboxEnvelope.create!(
        email_normalized: @email_normalized,
        payload: {
          "field1" => {
            value: "value2",
            strategy: "upsert",
            modified_at: (base_time + 1.minute).iso8601
          }
        },
        status: :queued,
        provenance: build_test_provenance,
        sync_source_id: @sync_source.id
      )

      # Run the dispatch worker
      worker = LoopsDispatchWorker.new
      worker.perform

      # Verify the latest value was sent
      assert_not_nil sent_payload, "LoopsService.update_contact should have been called"
      assert_equal "value2", sent_payload["field1"],
        "Should send value2 (latest modified_at), regardless of key type"

    ensure
      # Restore original method
      LoopsService.define_singleton_method(:update_contact, original_update_contact)
    end
  end

  test "filters out unchanged values based on baseline" do
    # Track what gets sent to Loops API
    sent_payload = nil
    call_count = 0

    # Mock LoopsService.update_contact to capture what's actually sent
    original_update_contact = LoopsService.method(:update_contact)
    LoopsService.define_singleton_method(:update_contact) do |email:, **kwargs|
      sent_payload = kwargs.dup
      call_count += 1
      { "success" => true, "id" => "test-request-123" }
    end

    begin
      base_time = Time.parse("2025-11-02T10:00:00Z")

      # First envelope - sets baseline
      envelope1 = LoopsOutboxEnvelope.create!(
        email_normalized: @email_normalized,
        payload: {
          "field1" => {
            "value" => "value1",
            "strategy" => "upsert",
            "modified_at" => base_time.iso8601
          }
        },
        status: :queued,
        provenance: build_test_provenance,
        sync_source_id: @sync_source.id
      )

      # Run worker first time - should send value1
      worker = LoopsDispatchWorker.new
      worker.perform

      assert_equal 1, call_count, "First call should send value1"
      assert_equal "value1", sent_payload["field1"], "First call should send value1"

      # Reset tracking
      sent_payload = nil

      # Second envelope with same value - should be filtered out
      envelope2 = LoopsOutboxEnvelope.create!(
        email_normalized: @email_normalized,
        payload: {
          "field1" => {
            "value" => "value1",  # Same value as baseline
            "strategy" => "upsert",
            "modified_at" => (base_time + 1.minute).iso8601
          }
        },
        status: :queued,
        provenance: build_test_provenance,
        sync_source_id: @sync_source.id
      )

      # Run worker second time - should not send (filtered by baseline)
      worker.perform

      # Should not have been called again (value unchanged)
      assert_equal 1, call_count, "Second call should not happen (value unchanged)"
      assert_equal "ignored_noop", envelope2.reload.status,
        "Envelope2 should be marked as ignored_noop"

      # Third envelope with different value - should be sent
      envelope3 = LoopsOutboxEnvelope.create!(
        email_normalized: @email_normalized,
        payload: {
          "field1" => {
            "value" => "value2",  # Different value
            "strategy" => "upsert",
            "modified_at" => (base_time + 2.minutes).iso8601
          }
        },
        status: :queued,
        provenance: build_test_provenance,
        sync_source_id: @sync_source.id
      )

      # Run worker third time - should send value2
      worker.perform

      assert_equal 2, call_count, "Third call should send value2"
      assert_equal "value2", sent_payload["field1"], "Third call should send value2"

    ensure
      # Restore original method
      LoopsService.define_singleton_method(:update_contact, original_update_contact)
    end
  end

  test "validates merging behavior with multiple queued envelopes" do
    # Track what gets sent to Loops API
    sent_payloads = []

    # Mock LoopsService.update_contact to capture what's actually sent
    original_update_contact = LoopsService.method(:update_contact)
    LoopsService.define_singleton_method(:update_contact) do |email:, **kwargs|
      sent_payloads << kwargs.dup
      { "success" => true, "id" => "test-request-123" }
    end

    begin
      base_time = Time.parse("2025-11-02T10:00:00Z")

      # Create multiple envelopes with overlapping and different fields
      # Scenario: Multiple rapid changes to same field, plus some different fields

      envelope1 = LoopsOutboxEnvelope.create!(
        email_normalized: @email_normalized,
        payload: {
          "field1" => {
            "value" => "initial",
            "strategy" => "upsert",
            "modified_at" => base_time.iso8601
          },
          "field2" => {
            "value" => "static",
            "strategy" => "upsert",
            "modified_at" => base_time.iso8601
          }
        },
        status: :queued,
        provenance: build_test_provenance,
        sync_source_id: @sync_source.id
      )

      envelope2 = LoopsOutboxEnvelope.create!(
        email_normalized: @email_normalized,
        payload: {
          "field1" => {
            "value" => "updated1",
            "strategy" => "upsert",
            "modified_at" => (base_time + 10.seconds).iso8601
          }
        },
        status: :queued,
        provenance: build_test_provenance,
        sync_source_id: @sync_source.id
      )

      envelope3 = LoopsOutboxEnvelope.create!(
        email_normalized: @email_normalized,
        payload: {
          "field1" => {
            "value" => "updated2",
            "strategy" => "upsert",
            "modified_at" => (base_time + 20.seconds).iso8601
          },
          "field3" => {
            "value" => "new_field",
            "strategy" => "upsert",
            "modified_at" => (base_time + 20.seconds).iso8601
          }
        },
        status: :queued,
        provenance: build_test_provenance,
        sync_source_id: @sync_source.id
      )

      envelope4 = LoopsOutboxEnvelope.create!(
        email_normalized: @email_normalized,
        payload: {
          "field1" => {
            "value" => "final",
            "strategy" => "upsert",
            "modified_at" => (base_time + 30.seconds).iso8601  # Latest for field1
          }
        },
        status: :queued,
        provenance: build_test_provenance,
        sync_source_id: @sync_source.id
      )

      # Run the dispatch worker - should process all queued envelopes for this email
      worker = LoopsDispatchWorker.new
      worker.perform

      # Verify all envelopes were processed
      assert_equal "sent", envelope1.reload.status, "Envelope1 should be marked as sent"
      assert_equal "sent", envelope2.reload.status, "Envelope2 should be marked as sent"
      assert_equal "sent", envelope3.reload.status, "Envelope3 should be marked as sent"
      assert_equal "sent", envelope4.reload.status, "Envelope4 should be marked as sent"

      # Verify what was actually sent
      assert_equal 1, sent_payloads.length, "Should call LoopsService.update_contact exactly once"

      final_payload = sent_payloads.first
      assert_not_nil final_payload, "LoopsService.update_contact should have been called"

      # field1 should have the latest value (from envelope4)
      assert_equal "final", final_payload["field1"],
        "field1 should have latest value 'final' (from envelope4), but got #{final_payload['field1']}"

      # field2 should be present (from envelope1)
      assert_equal "static", final_payload["field2"],
        "field2 should have value 'static' (from envelope1), but got #{final_payload['field2']}"

      # field3 should be present (from envelope3)
      assert_equal "new_field", final_payload["field3"],
        "field3 should have value 'new_field' (from envelope3), but got #{final_payload['field3']}"

      # Should have exactly 3 fields
      assert_equal 3, final_payload.keys.size,
        "Should send exactly 3 fields, but got #{final_payload.keys.inspect}"

    ensure
      # Restore original method
      LoopsService.define_singleton_method(:update_contact, original_update_contact)
    end
  end

  test "handles legacy payloads with type field" do
    # Track what gets sent to Loops API
    sent_payload = nil

    # Mock LoopsService.update_contact to capture what's actually sent
    original_update_contact = LoopsService.method(:update_contact)
    LoopsService.define_singleton_method(:update_contact) do |email:, **kwargs|
      sent_payload = kwargs.dup
      { "success" => true, "id" => "test-request-123" }
    end

    begin
      base_time = Time.parse("2025-11-02T10:00:00Z")

      # Envelope with legacy "type" field (from old code)
      envelope1 = LoopsOutboxEnvelope.create!(
        email_normalized: @email_normalized,
        payload: {
          "field1" => {
            "value" => "value1",
            "strategy" => "upsert",
            "type" => "string",  # Legacy field
            "modified_at" => base_time.iso8601
          }
        },
        status: :queued,
        provenance: build_test_provenance,
        sync_source_id: @sync_source.id
      )

      # Envelope without type field (new format)
      envelope2 = LoopsOutboxEnvelope.create!(
        email_normalized: @email_normalized,
        payload: {
          "field1" => {
            "value" => "value2",
            "strategy" => "upsert",
            "modified_at" => (base_time + 1.minute).iso8601
          }
        },
        status: :queued,
        provenance: build_test_provenance,
        sync_source_id: @sync_source.id
      )

      # Run the dispatch worker
      worker = LoopsDispatchWorker.new
      worker.perform

      # Verify the latest value was sent (ignoring type field)
      assert_not_nil sent_payload, "LoopsService.update_contact should have been called"
      assert_equal "value2", sent_payload["field1"],
        "Should send value2 (latest modified_at), ignoring type field"

      # Verify type field is not included in what's sent to Loops API
      field_data = envelope2.reload.payload["field1"]
      assert_not_nil field_data, "Should have field data"
      # The type field might exist in the envelope payload, but shouldn't be sent to Loops
      # (apply_strategies only extracts the value)

    ensure
      # Restore original method
      LoopsService.define_singleton_method(:update_contact, original_update_contact)
    end
  end

  test "override strategy fields bypass baseline filtering even when null value matches baseline" do
    # Track what gets sent to Loops API
    sent_payload = nil

    # Mock LoopsService.update_contact to capture what's actually sent
    original_update_contact = LoopsService.method(:update_contact)
    LoopsService.define_singleton_method(:update_contact) do |email:, **kwargs|
      sent_payload = kwargs.dup
      { "success" => true, "id" => "test-request-123" }
    end

    begin
      # Create a baseline with null value
      baseline = LoopsFieldBaseline.create!(
        email_normalized: @email_normalized,
        field_name: "overrideField",
        last_sent_value: nil,
        last_sent_at: Time.current - 1.day,
        expires_at: Time.current + 90.days
      )

      # Create envelope with override strategy and null value (same as baseline)
      envelope = LoopsOutboxEnvelope.create!(
        email_normalized: @email_normalized,
        payload: {
          "overrideField" => {
            "value" => nil,
            "strategy" => "override",
            "modified_at" => Time.current.iso8601
          }
        },
        status: :queued,
        provenance: build_test_provenance,
        sync_source_id: @sync_source.id
      )

      # Run the dispatch worker
      worker = LoopsDispatchWorker.new
      worker.perform

      # Verify envelope was processed
      assert_equal "sent", envelope.reload.status, "Envelope should be marked as sent"

      # Verify the null value was sent despite matching baseline
      assert_not_nil sent_payload, "LoopsService.update_contact should have been called"
      assert sent_payload.key?("overrideField"), "overrideField should be in payload"
      assert_nil sent_payload["overrideField"], "overrideField should be nil/null"

      # Verify baseline was updated
      baseline.reload
      assert_nil baseline.last_sent_value, "Baseline should reflect null value"

    ensure
      # Restore original method
      LoopsService.define_singleton_method(:update_contact, original_update_contact)
    end
  end

  test "upsert strategy fields with null are filtered out by strategy application" do
    # Track what gets sent to Loops API
    sent_payload = nil

    # Mock LoopsService.update_contact to capture what's actually sent
    original_update_contact = LoopsService.method(:update_contact)
    LoopsService.define_singleton_method(:update_contact) do |email:, **kwargs|
      sent_payload = kwargs.dup
      { "success" => true, "id" => "test-request-123" }
    end

    begin
      # Create envelope with upsert strategy and null value
      envelope = LoopsOutboxEnvelope.create!(
        email_normalized: @email_normalized,
        payload: {
          "upsertField" => {
            "value" => nil,
            "strategy" => "upsert",
            "modified_at" => Time.current.iso8601
          }
        },
        status: :queued,
        provenance: build_test_provenance,
        sync_source_id: @sync_source.id
      )

      # Run the dispatch worker
      worker = LoopsDispatchWorker.new
      worker.perform

      # Verify envelope was marked as ignored_noop (all fields filtered by strategy)
      assert_equal "ignored_noop", envelope.reload.status, "Envelope should be ignored when upsert field has null value"

      # Verify nothing was sent
      assert_nil sent_payload, "LoopsService.update_contact should NOT have been called for null upsert field"

    ensure
      # Restore original method
      LoopsService.define_singleton_method(:update_contact, original_update_contact)
    end
  end

  private

  def build_test_provenance
    {
      sync_source_id: @sync_source.id,
      sync_source_type: "airtable",
      sync_source_table_id: "tblTest123",
      sync_source_record_id: "recTest456",
      fields: [ {
        sync_source_field_id: "fldTest789",
        sync_source_field_name: "Loops - TestField",
        former_sync_source_value: nil,
        new_sync_source_value: "test_value",
        modified_at: Time.current.iso8601
      } ],
      created_from: "airtable_poller",
      sync_source_metadata: {
        source_id: @sync_source.source_id
      }
    }
  end

  def cleanup_advisory_locks
    # Clean up any advisory locks that might be left over from tests
    connection = ApplicationRecord.connection
    connection.execute("SELECT pg_advisory_unlock_all()")
  rescue => e
    Rails.logger.debug("Advisory lock cleanup: #{e.message}") if defined?(Rails)
  end
end
