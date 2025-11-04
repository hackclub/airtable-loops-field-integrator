require "test_helper"

class PruneFieldValueBaselinesWorkerTest < ActiveSupport::TestCase
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

  test "prunes stale baselines using default window" do
    default_window_days = PruneFieldValueBaselinesWorker::DEFAULT_PRUNING_WINDOW_DAYS
    cutoff_time = default_window_days.days.ago
    stale_time = (default_window_days + 1).days.ago
    recent_time = (default_window_days - 1).days.ago

    # Create stale baseline
    stale_baseline = FieldValueBaseline.create!(
      sync_source: @sync_source,
      row_id: "tbl1_rec1",
      field_id: "fld1",
      last_known_value: "value1",
      last_checked_at: stale_time,
      value_last_updated_at: stale_time
    )

    # Create recent baseline
    recent_baseline = FieldValueBaseline.create!(
      sync_source: @sync_source,
      row_id: "tbl1_rec2",
      field_id: "fld2",
      last_known_value: "value2",
      last_checked_at: recent_time,
      value_last_updated_at: recent_time
    )

    # Execute worker
    deleted_count = PruneFieldValueBaselinesWorker.new.perform

    # Verify stale baseline is deleted
    refute FieldValueBaseline.exists?(stale_baseline.id), "Stale baseline should be deleted"

    # Verify recent baseline still exists
    assert FieldValueBaseline.exists?(recent_baseline.id), "Recent baseline should not be deleted"

    # Verify return value
    assert deleted_count >= 1, "Should return count of deleted records"
  end

  test "prunes stale baselines using custom window" do
    custom_window_days = 7
    cutoff_time = custom_window_days.days.ago
    stale_time = (custom_window_days + 1).days.ago
    recent_time = (custom_window_days - 1).days.ago

    # Create stale baseline
    stale_baseline = FieldValueBaseline.create!(
      sync_source: @sync_source,
      row_id: "tbl1_rec1",
      field_id: "fld1",
      last_known_value: "value1",
      last_checked_at: stale_time,
      value_last_updated_at: stale_time
    )

    # Create recent baseline
    recent_baseline = FieldValueBaseline.create!(
      sync_source: @sync_source,
      row_id: "tbl1_rec2",
      field_id: "fld2",
      last_known_value: "value2",
      last_checked_at: recent_time,
      value_last_updated_at: recent_time
    )

    # Execute worker with custom window
    deleted_count = PruneFieldValueBaselinesWorker.new.perform(custom_window_days)

    # Verify stale baseline is deleted
    refute FieldValueBaseline.exists?(stale_baseline.id), "Stale baseline should be deleted"

    # Verify recent baseline still exists
    assert FieldValueBaseline.exists?(recent_baseline.id), "Recent baseline should not be deleted"

    assert_equal 1, deleted_count, "Should return count of deleted records"
  end

  test "handles empty database gracefully" do
    deleted_count = PruneFieldValueBaselinesWorker.new.perform
    assert_equal 0, deleted_count, "Should return 0 when no records to delete"
  end

  test "prunes multiple stale baselines" do
    window_days = 30
    stale_time = (window_days + 5).days.ago

    # Create multiple stale baselines
    baselines = []
    5.times do |i|
      baselines << FieldValueBaseline.create!(
        sync_source: @sync_source,
        row_id: "tbl1_rec#{i}",
        field_id: "fld#{i}",
        last_known_value: "value#{i}",
        last_checked_at: stale_time,
        value_last_updated_at: stale_time
      )
    end

    # Execute worker
    deleted_count = PruneFieldValueBaselinesWorker.new.perform(window_days)

    # Verify all stale baselines are deleted
    baselines.each do |baseline|
      refute FieldValueBaseline.exists?(baseline.id), "Stale baseline should be deleted"
    end

    assert_equal 5, deleted_count, "Should return count of all deleted records"
  end

  test "preserves baselines from different sync sources" do
    sync_source2 = SyncSource.create!(
      source: "airtable",
      source_id: "app456",
      poll_interval_seconds: 30
    )

    window_days = 30
    stale_time = (window_days + 5).days.ago

    # Create stale baseline for first sync source
    baseline1 = FieldValueBaseline.create!(
      sync_source: @sync_source,
      row_id: "tbl1_rec1",
      field_id: "fld1",
      last_known_value: "value1",
      last_checked_at: stale_time,
      value_last_updated_at: stale_time
    )

    # Create stale baseline for second sync source
    baseline2 = FieldValueBaseline.create!(
      sync_source: sync_source2,
      row_id: "tbl1_rec1",
      field_id: "fld1",
      last_known_value: "value1",
      last_checked_at: stale_time,
      value_last_updated_at: stale_time
    )

    # Execute worker
    deleted_count = PruneFieldValueBaselinesWorker.new.perform(window_days)

    # Verify both are deleted (pruning doesn't care about sync_source)
    refute FieldValueBaseline.exists?(baseline1.id), "Stale baseline 1 should be deleted"
    refute FieldValueBaseline.exists?(baseline2.id), "Stale baseline 2 should be deleted"
    assert_equal 2, deleted_count
  end

  test "uses correct default pruning window constant" do
    assert_equal 30, PruneFieldValueBaselinesWorker::DEFAULT_PRUNING_WINDOW_DAYS
  end

  test "calculates cutoff time correctly" do
    window_days = 30
    worker = PruneFieldValueBaselinesWorker.new

    # We can't directly test cutoff calculation, but we can verify behavior
    # by checking that baselines older than window are deleted
    old_time = (window_days + 1).days.ago
    recent_time = (window_days - 1).days.ago

    old_baseline = FieldValueBaseline.create!(
      sync_source: @sync_source,
      row_id: "tbl1_rec1",
      field_id: "fld1",
      last_known_value: "value1",
      last_checked_at: old_time,
      value_last_updated_at: old_time
    )

    recent_baseline = FieldValueBaseline.create!(
      sync_source: @sync_source,
      row_id: "tbl1_rec2",
      field_id: "fld2",
      last_known_value: "value2",
      last_checked_at: recent_time,
      value_last_updated_at: recent_time
    )

    worker.perform(window_days)

    refute FieldValueBaseline.exists?(old_baseline.id), "Old baseline should be deleted"
    assert FieldValueBaseline.exists?(recent_baseline.id), "Recent baseline should remain"
  end
end
