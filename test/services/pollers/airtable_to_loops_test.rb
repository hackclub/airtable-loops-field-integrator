require "test_helper"

module Pollers
  class AirtableToLoopsTest < ActiveSupport::TestCase
    def setup
      @sync_source = SyncSource.create!(
        source: "airtable",
        source_id: "app123",
        poll_interval_seconds: 30
      )
    end

    def teardown
      FieldValueBaseline.destroy_all
      SyncSource.destroy_all
    end

    test "detect_changes only creates baselines for Loops fields" do
      # Create mock table schema with both Loops and non-Loops fields
      table = {
        "fields" => [
          { "id" => "fldEmail", "name" => "email" },
          { "id" => "fldLoops1", "name" => "Loops - firstName" },
          { "id" => "fldLoops2", "name" => "Loops - lastName" },
          { "id" => "fldNonLoops1", "name" => "Zapier - Added to Midnight Loops list at" },
          { "id" => "fldNonLoops2", "name" => "referral_target" },
          { "id" => "fldNonLoops3", "name" => "inbound_referrals" }
        ]
      }

      email_field = { "id" => "fldEmail", "name" => "email" }

      # Find Loops fields (this matches the actual logic)
      loops_fields = {}
      table["fields"].each do |field|
        field_name = field["name"] || ""
        loops_pattern = /\ALoops\s*-\s*(Override\s*-\s*)?[a-z][a-zA-Z0-9]*\z/i
        if field_name.strip.match?(loops_pattern)
          field_name_without_prefix = field_name.sub(/\ALoops\s*-\s*(Override\s*-\s*)?/i, "")
          if field_name_without_prefix =~ /\A[a-z]/
            loops_fields[field["id"]] = field
          end
        end
      end

      # Verify we found the Loops fields
      assert_equal 2, loops_fields.size, "Should find 2 Loops fields"
      assert loops_fields.key?("fldLoops1"), "Should include Loops - firstName"
      assert loops_fields.key?("fldLoops2"), "Should include Loops - lastName"

      # Create mock records with values for all fields
      records = [
        {
          "id" => "rec123",
          "fields" => {
            "email" => "test@example.com",
            "Loops - firstName" => "John",
            "Loops - lastName" => "Doe",
            "Zapier - Added to Midnight Loops list at" => "2024-01-01",
            "referral_target" => "target123",
            "inbound_referrals" => [ "ref1", "ref2" ]
          }
        }
      ]

      # Call detect_changes
      poller = Pollers::AirtableToLoops.new
      changed_records = poller.send(
        :detect_changes,
        @sync_source,
        "base123",
        "tbl123",
        records,
        table,
        email_field,
        loops_fields
      )

      # Verify only Loops field baselines were created
      baselines = FieldValueBaseline.where(sync_source: @sync_source)
      baseline_field_ids = baselines.pluck(:field_id)

      # Should only have baselines for Loops fields (format: "field_id/field_name")
      assert_equal 2, baselines.count, "Should create 2 baselines (one for each Loops field)"

      assert baseline_field_ids.any? { |id| id.include?("Loops - firstName") },
        "Should have baseline for Loops - firstName"
      assert baseline_field_ids.any? { |id| id.include?("Loops - lastName") },
        "Should have baseline for Loops - lastName"

      # Verify non-Loops fields did NOT create baselines
      assert baseline_field_ids.none? { |id| id.include?("Zapier") },
        "Should NOT have baseline for Zapier field"
      assert baseline_field_ids.none? { |id| id.include?("referral_target") },
        "Should NOT have baseline for referral_target"
      assert baseline_field_ids.none? { |id| id.include?("inbound_referrals") },
        "Should NOT have baseline for inbound_referrals"
    end

    test "detect_changes correctly identifies changed Loops fields" do
      table = {
        "fields" => [
          { "id" => "fldEmail", "name" => "email" },
          { "id" => "fldLoops1", "name" => "Loops - firstName" }
        ]
      }

      email_field = { "id" => "fldEmail", "name" => "email" }
      loops_fields = { "fldLoops1" => { "id" => "fldLoops1", "name" => "Loops - firstName" } }

      # First record with initial value
      records1 = [
        {
          "id" => "rec123",
          "fields" => {
            "email" => "test@example.com",
            "Loops - firstName" => "John"
          }
        }
      ]

      poller = Pollers::AirtableToLoops.new

      # First call - should detect change (first time)
      changed_records1 = poller.send(
        :detect_changes,
        @sync_source,
        "base123",
        "tbl123",
        records1,
        table,
        email_field,
        loops_fields
      )

      assert_equal 1, changed_records1.size, "Should detect change on first time"
      assert_equal 1, changed_records1.first[:changedValues].size, "Should have one changed field"

      # Second call with same value - should not detect change
      changed_records2 = poller.send(
        :detect_changes,
        @sync_source,
        "base123",
        "tbl123",
        records1,
        table,
        email_field,
        loops_fields
      )

      assert_equal 0, changed_records2.size, "Should not detect change for same value"

      # Third call with different value - should detect change
      records2 = [
        {
          "id" => "rec123",
          "fields" => {
            "email" => "test@example.com",
            "Loops - firstName" => "Jane"
          }
        }
      ]

      changed_records3 = poller.send(
        :detect_changes,
        @sync_source,
        "base123",
        "tbl123",
        records2,
        table,
        email_field,
        loops_fields
      )

      assert_equal 1, changed_records3.size, "Should detect change when value changes"
      assert_equal "Jane", changed_records3.first[:changedValues].values.first["value"]
      assert_equal "John", changed_records3.first[:changedValues].values.first["old_value"]
    end

    test "detect_changes handles empty loops_fields gracefully" do
      table = {
        "fields" => [
          { "id" => "fldEmail", "name" => "email" },
          { "id" => "fldNonLoops1", "name" => "some_field" }
        ]
      }

      email_field = { "id" => "fldEmail", "name" => "email" }
      loops_fields = {} # Empty - no Loops fields

      records = [
        {
          "id" => "rec123",
          "fields" => {
            "email" => "test@example.com",
            "some_field" => "some_value"
          }
        }
      ]

      poller = Pollers::AirtableToLoops.new
      changed_records = poller.send(
        :detect_changes,
        @sync_source,
        "base123",
        "tbl123",
        records,
        table,
        email_field,
        loops_fields
      )

      # Should return empty array since no Loops fields exist
      assert_equal 0, changed_records.size, "Should not detect changes when no Loops fields exist"

      # Should not create any baselines
      baselines = FieldValueBaseline.where(sync_source: @sync_source)
      assert_equal 0, baselines.count, "Should not create any baselines when no Loops fields exist"
    end

    test "detect_changes does not create baselines for exact non-Loops fields from user report" do
      # Test using the exact field names from the user's CSV data
      table = {
        "fields" => [
          { "id" => "fldEmail", "name" => "email" },
          { "id" => "fldimgRW3BVDJPULl", "name" => "Loops - lastName" },
          { "id" => "fldA6xic5Me6IxBed", "name" => "Zapier - Added to Midnight Loops list at" },
          { "id" => "fldW9AgGpoU2VHaeP", "name" => "referral_target" },
          { "id" => "fldQzRm5jW3KnzGkk", "name" => "inbound_referrals" },
          { "id" => "fldrLrAoZ0Cz7ZMai", "name" => "number_of_referrals" },
          { "id" => "fldPv2jEDihPvDOuZ", "name" => "Loops - birthday" },
          { "id" => "fldA1EtUNrU2OZiXW", "name" => "Loops - firstName" }
        ]
      }

      email_field = { "id" => "fldEmail", "name" => "email" }

      # Find Loops fields using the actual find_loops_fields logic
      poller = Pollers::AirtableToLoops.new
      loops_fields = poller.send(:find_loops_fields, table)

      # Verify we found only Loops fields
      assert_equal 3, loops_fields.size, "Should find 3 Loops fields"
      assert loops_fields.key?("fldimgRW3BVDJPULl"), "Should include Loops - lastName"
      assert loops_fields.key?("fldPv2jEDihPvDOuZ"), "Should include Loops - birthday"
      assert loops_fields.key?("fldA1EtUNrU2OZiXW"), "Should include Loops - firstName"

      # Create mock record matching user's data
      records = [
        {
          "id" => "recBV0ElVYe4YEFzW",
          "fields" => {
            "email" => "test@example.com",
            "Loops - lastName" => "Sasha",
            "Zapier - Added to Midnight Loops list at" => nil,
            "referral_target" => [ "recBV0ElVYe4YEFzW" ],
            "inbound_referrals" => nil,
            "number_of_referrals" => 0,
            "Loops - birthday" => "2009-04-14",
            "Loops - firstName" => "Colomischi"
          }
        }
      ]

      # Call detect_changes
      changed_records = poller.send(
        :detect_changes,
        @sync_source,
        "base123",
        "tbldJ8CL1xt7qcnrM",
        records,
        table,
        email_field,
        loops_fields
      )

      # Verify only Loops field baselines were created
      baselines = FieldValueBaseline.where(sync_source: @sync_source)
      baseline_field_ids = baselines.pluck(:field_id)

      # Should only have baselines for Loops fields (format: "field_id/field_name")
      assert_equal 3, baselines.count, "Should create 3 baselines (one for each Loops field)"

      assert baseline_field_ids.any? { |id| id.include?("Loops - lastName") },
        "Should have baseline for Loops - lastName"
      assert baseline_field_ids.any? { |id| id.include?("Loops - birthday") },
        "Should have baseline for Loops - birthday"
      assert baseline_field_ids.any? { |id| id.include?("Loops - firstName") },
        "Should have baseline for Loops - firstName"

      # Verify non-Loops fields did NOT create baselines (exact field names from user's CSV)
      assert baseline_field_ids.none? { |id| id.include?("Zapier - Added to Midnight Loops list at") },
        "Should NOT have baseline for Zapier - Added to Midnight Loops list at"
      assert baseline_field_ids.none? { |id| id.include?("referral_target") },
        "Should NOT have baseline for referral_target"
      assert baseline_field_ids.none? { |id| id.include?("inbound_referrals") },
        "Should NOT have baseline for inbound_referrals"
      assert baseline_field_ids.none? { |id| id.include?("number_of_referrals") },
        "Should NOT have baseline for number_of_referrals"
    end
  end
end
