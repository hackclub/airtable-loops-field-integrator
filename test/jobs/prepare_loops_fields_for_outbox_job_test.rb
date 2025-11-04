require "test_helper"

class PrepareLoopsFieldsForOutboxJobTest < ActiveJob::TestCase
  # Disable parallelization for this test class since we're testing database interactions
  parallelize(workers: 1)

  def setup
    @sync_source = SyncSource.create!(
      source: "airtable",
      source_id: "app123",
      poll_interval_seconds: 30
    )

    @email = "test@example.com"
    @table_id = "tbl123"
    @record_id = "rec123"
    @field_key = "fldMXhauv0JDKMq6h/Loops - tmpZachLoopsApiTest"

    # Clean up any existing data
    LoopsOutboxEnvelope.destroy_all
  end

  def teardown
    LoopsOutboxEnvelope.destroy_all
    SyncSource.destroy_all
  end

  test "sets former_sync_source_value when old_value is present in changed_fields" do
    changed_fields = {
      @field_key => {
        "value" => "new_value",
        "old_value" => "old_value",
        "modified_at" => Time.current.iso8601
      }
    }

    PrepareLoopsFieldsForOutboxJob.new.perform(
      @email,
      @sync_source.id,
      @table_id,
      @record_id,
      changed_fields
    )

    envelope = LoopsOutboxEnvelope.last
    assert_not_nil envelope, "Envelope should be created"

    # Check that former_sync_source_value is set correctly in provenance
    field_provenance = envelope.provenance["fields"]&.first
    assert_not_nil field_provenance, "Field provenance should exist"
    assert_equal "old_value", field_provenance["former_sync_source_value"],
      "former_sync_source_value should be set to old_value from changed_fields"
    assert_equal "new_value", field_provenance["new_sync_source_value"],
      "new_sync_source_value should be set to value from changed_fields"
  end

  test "sets former_sync_source_value to nil when old_value is nil (first time)" do
    changed_fields = {
      @field_key => {
        "value" => "new_value",
        "old_value" => nil,
        "modified_at" => Time.current.iso8601
      }
    }

    PrepareLoopsFieldsForOutboxJob.new.perform(
      @email,
      @sync_source.id,
      @table_id,
      @record_id,
      changed_fields
    )

    envelope = LoopsOutboxEnvelope.last
    assert_not_nil envelope, "Envelope should be created"

    # Check that former_sync_source_value is nil when old_value is nil
    field_provenance = envelope.provenance["fields"]&.first
    assert_not_nil field_provenance, "Field provenance should exist"
    assert_nil field_provenance["former_sync_source_value"],
      "former_sync_source_value should be nil when old_value is nil"
    assert_equal "new_value", field_provenance["new_sync_source_value"],
      "new_sync_source_value should be set to value from changed_fields"
  end

  test "sets former_sync_source_value to nil when old_value key is missing" do
    changed_fields = {
      @field_key => {
        "value" => "new_value",
        "modified_at" => Time.current.iso8601
        # old_value key is missing
      }
    }

    PrepareLoopsFieldsForOutboxJob.new.perform(
      @email,
      @sync_source.id,
      @table_id,
      @record_id,
      changed_fields
    )

    envelope = LoopsOutboxEnvelope.last
    assert_not_nil envelope, "Envelope should be created"

    # Check that former_sync_source_value is nil when old_value key is missing
    field_provenance = envelope.provenance["fields"]&.first
    assert_not_nil field_provenance, "Field provenance should exist"
    assert_nil field_provenance["former_sync_source_value"],
      "former_sync_source_value should be nil when old_value key is missing"
    assert_equal "new_value", field_provenance["new_sync_source_value"],
      "new_sync_source_value should be set to value from changed_fields"
  end

  test "creates envelope with correct payload structure" do
    changed_fields = {
      @field_key => {
        "value" => "test_value",
        "old_value" => "old_test_value",
        "modified_at" => Time.current.iso8601
      }
    }

    PrepareLoopsFieldsForOutboxJob.new.perform(
      @email,
      @sync_source.id,
      @table_id,
      @record_id,
      changed_fields
    )

    envelope = LoopsOutboxEnvelope.last
    assert_not_nil envelope, "Envelope should be created"
    assert_equal "queued", envelope.status
    assert_equal EmailNormalizer.normalize(@email), envelope.email_normalized

    # Check payload structure
    assert envelope.payload.key?("tmpZachLoopsApiTest"), "Payload should contain the test field name"
    field_data = envelope.payload["tmpZachLoopsApiTest"]
    assert_equal "test_value", field_data["value"]
    assert_equal "upsert", field_data["strategy"]
    assert_not_nil field_data["modified_at"]
  end

  test "includes correct provenance metadata" do
    changed_fields = {
      @field_key => {
        "value" => "test_value",
        "old_value" => "old_test_value",
        "modified_at" => Time.current.iso8601
      }
    }

    PrepareLoopsFieldsForOutboxJob.new.perform(
      @email,
      @sync_source.id,
      @table_id,
      @record_id,
      changed_fields
    )

    envelope = LoopsOutboxEnvelope.last
    provenance = envelope.provenance

    assert_equal @sync_source.id, provenance["sync_source_id"]
    assert_equal "airtable", provenance["sync_source_type"]
    assert_equal @table_id, provenance["sync_source_table_id"]
    assert_equal @record_id, provenance["sync_source_record_id"]
    assert_equal "airtable_poller", provenance["created_from"]
    assert_not_nil provenance["sync_source_metadata"]
    assert_equal "app123", provenance["sync_source_metadata"]["source_id"]
  end

  test "handles missing changed_fields gracefully" do
    changed_fields = {}

    PrepareLoopsFieldsForOutboxJob.new.perform(
      @email,
      @sync_source.id,
      @table_id,
      @record_id,
      changed_fields
    )

    # No envelope should be created when there are no Loops fields
    envelope = LoopsOutboxEnvelope.last
    assert_nil envelope, "No envelope should be created when changed_fields is empty or contains no Loops fields"
  end

  test "processes Loops - Override - fields correctly" do
    override_field_key = "fldOverride123/Loops - Override - tmpZachLoopsApiTest2"
    changed_fields = {
      override_field_key => {
        "value" => "tmpZachLoopsApiTest2",
        "old_value" => "old_value",
        "modified_at" => Time.current.iso8601
      }
    }

    PrepareLoopsFieldsForOutboxJob.new.perform(
      @email,
      @sync_source.id,
      @table_id,
      @record_id,
      changed_fields
    )

    envelope = LoopsOutboxEnvelope.last
    assert_not_nil envelope, "Envelope should be created"

    # Check that field name is correctly mapped (prefix stripped)
    assert envelope.payload.key?("tmpZachLoopsApiTest2"), "Payload should contain the mapped field name"
    
    # Check that strategy is :override
    field_data = envelope.payload["tmpZachLoopsApiTest2"]
    assert_equal "override", field_data["strategy"], "Strategy should be override for Override fields"
    assert_equal "tmpZachLoopsApiTest2", field_data["value"]

    # Check provenance
    field_provenance = envelope.provenance["fields"]&.first
    assert_not_nil field_provenance, "Field provenance should exist"
    assert_equal "Loops - Override - tmpZachLoopsApiTest2", field_provenance["sync_source_field_name"]
    assert_equal "tmpZachLoopsApiTest2", field_provenance["new_sync_source_value"]
    assert_equal "old_value", field_provenance["former_sync_source_value"]
  end

  test "processes multiple Loops fields including Override fields" do
    changed_fields = {
      "fld123/Loops - tmpZachLoopsApiTest" => {
        "value" => "regular_value",
        "old_value" => "old_regular",
        "modified_at" => Time.current.iso8601
      },
      "fld456/Loops - Override - tmpZachLoopsApiTest2" => {
        "value" => "override_value",
        "old_value" => "old_override",
        "modified_at" => Time.current.iso8601
      }
    }

    PrepareLoopsFieldsForOutboxJob.new.perform(
      @email,
      @sync_source.id,
      @table_id,
      @record_id,
      changed_fields
    )

    envelope = LoopsOutboxEnvelope.last
    assert_not_nil envelope, "Envelope should be created"

    # Check both fields are in the payload
    assert envelope.payload.key?("tmpZachLoopsApiTest"), "Payload should contain regular field"
    assert envelope.payload.key?("tmpZachLoopsApiTest2"), "Payload should contain override field"

    # Check strategies
    assert_equal "upsert", envelope.payload["tmpZachLoopsApiTest"]["strategy"]
    assert_equal "override", envelope.payload["tmpZachLoopsApiTest2"]["strategy"]

    # Check values
    assert_equal "regular_value", envelope.payload["tmpZachLoopsApiTest"]["value"]
    assert_equal "override_value", envelope.payload["tmpZachLoopsApiTest2"]["value"]
  end

  test "skips fields that start with uppercase (not lowerCamelCase)" do
    changed_fields = {
      "fld123/Loops - Lists" => {  # Should NOT be processed
        "value" => "some_value",
        "old_value" => nil,
        "modified_at" => Time.current.iso8601
      },
      "fld456/Loops - tmpZachLoopsApiTest" => {  # Should be processed
        "value" => "valid_value",
        "old_value" => nil,
        "modified_at" => Time.current.iso8601
      }
    }

    PrepareLoopsFieldsForOutboxJob.new.perform(
      @email,
      @sync_source.id,
      @table_id,
      @record_id,
      changed_fields
    )

    envelope = LoopsOutboxEnvelope.last
    assert_not_nil envelope, "Envelope should be created"

    # Should NOT contain "Lists" field
    assert_not envelope.payload.key?("Lists"), "Should not process 'Loops - Lists' (starts with uppercase)"
    
    # Should contain the valid field
    assert envelope.payload.key?("tmpZachLoopsApiTest"), "Should process 'Loops - tmpZachLoopsApiTest'"
    assert_equal "valid_value", envelope.payload["tmpZachLoopsApiTest"]["value"]
    
    # Should only have one field in payload
    assert_equal 1, envelope.payload.keys.size, "Should only process one field"
  end
end

