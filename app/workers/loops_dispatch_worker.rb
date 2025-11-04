require "digest"
require "securerandom"
require_relative "../lib/email_normalizer"

class LoopsDispatchWorker
  include Sidekiq::Worker

  sidekiq_options queue: :default

  # Advisory lock namespace for per-email locking (same as PrepareLoopsFieldsForOutboxJob)
  ADVISORY_LOCK_NAMESPACE = 0x504C4600  # ASCII: "PLF" (PrepareLoopsFields)

  BATCH_SIZE = 50  # Process up to 50 emails per run

  def perform
    # Batch envelopes by email using FOR UPDATE SKIP LOCKED for concurrent workers
    processed_count = 0

    loop do
      # Get a batch of queued envelopes (skip locked to allow concurrent workers)
      # Lock the envelopes themselves, then group by email
      envelopes = LoopsOutboxEnvelope.queued
                                     .order(:created_at)
                                     .limit(BATCH_SIZE)
                                     .lock("FOR UPDATE SKIP LOCKED")
                                     .to_a

      break if envelopes.empty?

      # Group by email and process each email
      envelopes_by_email = envelopes.group_by(&:email_normalized)

      envelopes_by_email.each do |email_normalized, email_envelopes|
        process_email(email_normalized)
        processed_count += 1
      end
    end

    processed_count
  end

  private

  def process_email(email_normalized)
    # Acquire per-email advisory lock
    ActiveRecord::Base.connection_pool.with_connection do |connection|
      lock_key = email_to_lock_key(email_normalized)
      result = connection.execute(
        "SELECT pg_try_advisory_lock(#{lock_key})"
      )

      lock_acquired = result.first["pg_try_advisory_lock"]
      unless lock_acquired
        Rails.logger.debug("LoopsDispatchWorker: Skipping #{email_normalized} - already processing")
        return
      end

      begin
        # Load all queued envelopes for this email
        envelopes = LoopsOutboxEnvelope.queued
                                       .for_email(email_normalized)
                                       .order(:created_at)
                                       .to_a

        return if envelopes.empty?

        # Determine sync_source for this email batch
        sync_source = envelopes.first&.sync_source || SyncSource.find_by(id: envelopes.first&.provenance&.dig("sync_source_id"))

        # Preflight: check if contact exists and load baselines if needed
        # This can raise LoopsService::ApiError if email is invalid
        begin
        contact_exists = sync_source ? LoopsFieldBaseline.check_contact_existence_and_load_baselines(email_normalized: email_normalized) : true
        rescue LoopsService::ApiError => e
          # Mark envelopes as failed if preflight check fails (e.g., invalid email)
          Rails.logger.error("LoopsDispatchWorker: Preflight check failed for #{email_normalized}: #{e.class} - #{e.message}")
          ApplicationRecord.transaction do
            envelopes.each do |envelope|
              envelope.update_columns(
                status: :failed,
                error: {
                  message: e.message,
                  class: e.class.name,
                  stage: "preflight_check",
                  occurred_at: Time.current.iso8601
                },
                updated_at: Time.current
              )
            end
          end
          # Re-raise to mark job as failed
          raise
        end

        # Merge envelopes: combine payloads, latest modified_at wins per field
        merged_payload = merge_envelopes(envelopes)

        # If new contact, inject initial fields BEFORE baseline filtering
        if sync_source && !contact_exists
          initial_fields = LoopsFieldBaseline.initial_payload_for_new_contact(sync_source)
          initial_fields.each do |field_name, field_data|
            # Only add if not already present (queued envelopes take precedence)
            merged_payload[field_name] ||= field_data
          end
        end

        # Filter by loops_field_baselines AFTER merging
        filtered_payload = filter_by_baselines(email_normalized, merged_payload)

        if filtered_payload.empty?
          # Nothing to send - mark all as ignored_noop
          envelopes.each { |e| e.update!(status: :ignored_noop) }
          return
        end

        # Apply strategies and prepare payload for Loops API
        loops_payload = apply_strategies(filtered_payload)

        if loops_payload.empty?
          # All fields filtered out by strategy (:upsert skipping nil values)
          envelopes.each { |e| e.update!(status: :ignored_noop) }
          return
        end

        # Call LoopsService.update_contact (rate limiting handled internally)
        # All payload data is stored in DB: envelope.payload (what was queued),
        # audit records (what was sent + response), and baselines (what was persisted)
        request_id = nil
        response = nil
        begin
          response = LoopsService.update_contact(email: email_normalized, **loops_payload)

          # Fix response parsing: Loops API returns {"success"=>true, "id"=>"..."}
          # Use "id" as request_id if present, otherwise generate UUID
          request_id = response&.dig("id") || response&.dig("request_id") || SecureRandom.uuid

          # Validate that the update actually succeeded
          # Loops API returns {"success"=>true, "id"=>"..."} on success
          unless response && response["success"] == true
            error_msg = "Loops API update did not succeed. Response: #{response.inspect}"
            Rails.logger.error("LoopsDispatchWorker: #{error_msg}")

            # Wrap envelope updates in a transaction to ensure they're committed
            # Use update_columns to bypass validations and ensure persistence
            ApplicationRecord.transaction do
            envelopes.each do |envelope|
                envelope.update_columns(
                status: :failed,
                error: {
                  message: error_msg,
                  response: response,
                  loops_payload_sent: loops_payload,  # Store what was actually sent
                  occurred_at: Time.current.iso8601
                  },
                  updated_at: Time.current
              )
              end
            end
            # Raise exception after ensuring envelopes are marked as failed
            raise StandardError.new(error_msg)
          end
        rescue => e
          # Mark envelopes as failed and store full error details in DB for debugging
          Rails.logger.error("LoopsDispatchWorker: Error updating Loops contact: #{e.class} - #{e.message}")
          Rails.logger.error("LoopsDispatchWorker: Error backtrace: #{e.backtrace.first(5).join("\n")}")

          # Wrap envelope updates in a transaction to ensure they're committed
          # Use update_columns to bypass validations and ensure persistence
          ApplicationRecord.transaction do
          envelopes.each do |envelope|
              error_hash = {
                message: e.message,
                class: e.class.name,
                loops_payload_sent: loops_payload,  # Store what was actually sent
                backtrace: e.backtrace.first(10),  # Store backtrace for debugging
                occurred_at: Time.current.iso8601
              }
              # Include response if available (e.g., when error comes from unsuccessful API response)
              error_hash[:response] = response if defined?(response) && response
              
              envelope.update_columns(
                status: :failed,
                error: error_hash,
                updated_at: Time.current
            )
          end
          end
          # Re-raise exception after ensuring envelopes are marked as failed
          raise
        end

        # In DB transaction: update baselines, create audit records, mark envelopes
        ApplicationRecord.transaction do
          sent_fields = Set.new
          filtered_fields = Set.new

          filtered_payload.each do |field_name, field_data|
            if loops_payload.key?(field_name)
              sent_fields << field_name

              # Find or create baseline and capture old value BEFORE updating
              baseline = LoopsFieldBaseline.find_or_create_baseline(
                email_normalized: email_normalized,
                field_name: field_name
              )
              former_loops_value = baseline.last_sent_value

              # Extract value from field_data (handle both string and symbol keys)
              field_data_hash = field_data.is_a?(Hash) ? field_data : {}
              value_to_send = loops_payload[field_name]  # Use the value that was actually sent to Loops

              # Validate that the API call succeeded before updating baseline
              # This ensures baseline only reflects values that were actually persisted in Loops
              if response && response["success"] == true
                # Update baseline only after confirming successful API update
                baseline.update_sent_value(
                  value: value_to_send,
                  expires_in_days: 90
                )
              else
                Rails.logger.error("LoopsDispatchWorker: NOT updating baseline for #{field_name} - API call did not succeed")
                # Don't update baseline if API call failed
              end

              # Create audit record
              # Find provenance from first envelope (they should all have same provenance per email)
              provenance = envelopes.first.provenance

              # Extract field provenance - match by field name
              field_provenance = provenance["fields"]&.find { |f|
                # Match by field name - map back from loops_field_name to sync source field
                sync_source_field_name = f["sync_source_field_name"]
                sync_source_field_name&.sub(/\ALoops\s*-\s*/i, "") == field_name ||
                field_name == sync_source_field_name
              }

              # Build sync-source-agnostic provenance metadata for audit record
              # This stores sync-source-specific identifiers from the envelope provenance
              audit_provenance = {}

              # Store sync-source-agnostic identifiers
              audit_provenance["sync_source_type"] = provenance["sync_source_type"]

              # Add sync-source-specific metadata if present
              # Metadata comes from sync_source.metadata and includes source_id
              if provenance["sync_source_metadata"]
                # Store the sync-source-specific metadata generically
                # Each sync source type can structure this differently
                audit_provenance["sync_source_metadata"] = provenance["sync_source_metadata"]
              end

              # Create audit record only if API call succeeded
              # Store all debugging data: old/new values, request_id, provenance, response, and payload sent
              if response && response["success"] == true
                # Store response and full payload sent in provenance for debugging
                audit_provenance_with_response = audit_provenance.dup
                audit_provenance_with_response["loops_api_response"] = response
                audit_provenance_with_response["loops_payload_sent"] = loops_payload  # Store full payload that was sent

                LoopsContactChangeAudit.create!(
                  occurred_at: Time.current,
                  email_normalized: email_normalized,
                  field_name: field_name,
                  former_loops_value: former_loops_value,
                  new_loops_value: value_to_send,  # Use the value that was actually sent
                  former_sync_source_value: field_provenance&.dig("former_sync_source_value"),
                  new_sync_source_value: field_provenance&.dig("new_sync_source_value"),
                  strategy: (field_data_hash[:strategy] || field_data_hash["strategy"] || :upsert).to_s,
                  sync_source_id: provenance["sync_source_id"],
                  sync_source_table_id: provenance["sync_source_table_id"],
                  sync_source_record_id: provenance["sync_source_record_id"],
                  sync_source_field_id: field_provenance&.dig("sync_source_field_id"),
                  provenance: audit_provenance_with_response,
                  request_id: request_id
                )
              else
                Rails.logger.warn("LoopsDispatchWorker: NOT creating audit record for #{field_name} - API call did not succeed")
              end
            else
              filtered_fields << field_name
            end
          end

          # Determine final status
          if filtered_fields.empty?
            # All fields sent
            envelopes.each { |e| e.update!(status: :sent) }
          else
            # Some fields sent, some filtered
            envelopes.each { |e| e.update!(status: :partially_sent) }
          end
        end
      rescue => e
        # Catch any other unexpected errors in the processing pipeline
        # (errors from update_contact are handled in the inner rescue block)
        Rails.logger.error("LoopsDispatchWorker: Unexpected error processing #{email_normalized}: #{e.class} - #{e.message}")
        Rails.logger.error("LoopsDispatchWorker: Error backtrace: #{e.backtrace.first(10).join("\n")}")
        
        # Mark envelopes as failed if we have them loaded
        # Skip if envelopes are already marked as failed (e.g., from preflight check)
        if defined?(envelopes) && envelopes && !envelopes.empty?
          # Check if envelopes are already marked as failed
          already_failed = envelopes.all? { |e| e.reload.status == "failed" }
          
          unless already_failed
            ApplicationRecord.transaction do
              envelopes.each do |envelope|
                envelope.update_columns(
                  status: :failed,
                  error: {
                    message: e.message,
                    class: e.class.name,
                    stage: "processing",
                    backtrace: e.backtrace.first(10),
                    occurred_at: Time.current.iso8601
                  },
                  updated_at: Time.current
                )
              end
            end
          end
        end
        # Re-raise to mark job as failed
        raise
      ensure
        # Always release the lock
        connection.execute(
          "SELECT pg_advisory_unlock(#{lock_key})"
        )
      end
    end
  end

  # Hash email to integer for advisory lock (same as PrepareLoopsFieldsForOutboxJob)
  def email_to_lock_key(email)
    # Combine namespace and email hash into single bigint
    # Use first 8 bytes of SHA256 hash as integer, combine with namespace
    hash_int = Digest::SHA256.hexdigest(email)[0..15].to_i(16)
    # Combine namespace (upper 32 bits) and hash (lower 32 bits)
    (ADVISORY_LOCK_NAMESPACE.to_i << 32) | (hash_int & 0xFFFFFFFF)
  end

  # Merge multiple envelopes: combine payloads, latest modified_at wins per field
  def merge_envelopes(envelopes)
    merged = {}

    envelopes.each do |envelope|
      envelope.payload.each do |field_name, field_data|
        existing = merged[field_name]

        if existing.nil?
          merged[field_name] = field_data.dup
        else
          # Compare modified_at timestamps - keep latest
          # Handle both string and symbol keys (JSONB from DB has string keys)
          existing_hash = existing.is_a?(Hash) ? existing : {}
          field_data_hash = field_data.is_a?(Hash) ? field_data : {}

          existing_modified_at = existing_hash[:modified_at] || existing_hash["modified_at"]
          new_modified_at = field_data_hash[:modified_at] || field_data_hash["modified_at"]

          existing_time = Time.parse(existing_modified_at.to_s) rescue Time.at(0)
          new_time = Time.parse(new_modified_at.to_s) rescue Time.at(0)

          if new_time > existing_time
            merged[field_name] = field_data.dup
          end
        end
      end
    end

    merged
  end

  # Filter by loops_field_baselines: drop fields whose value equals baseline and hasn't expired
  # For :override strategy fields, always include (even if value matches baseline)
  def filter_by_baselines(email_normalized, merged_payload)
    filtered = {}

    merged_payload.each do |field_name, field_data|
      # Handle both string and symbol keys
      field_data_hash = field_data.is_a?(Hash) ? field_data : {}
      current_value = field_data_hash[:value] || field_data_hash["value"]
      strategy = (field_data_hash[:strategy] || field_data_hash["strategy"])&.to_sym || :upsert

      # For override strategy, always include (even if value matches baseline)
      # This allows override fields to explicitly set null values
      if strategy == :override
        filtered[field_name] = field_data
        next
      end

      baseline = LoopsFieldBaseline.find_by(
        email_normalized: email_normalized,
        field_name: field_name
      )

      if baseline.nil?
        # No baseline - include field
        filtered[field_name] = field_data
      elsif baseline.expires_at && baseline.expires_at < Time.current
        # Baseline expired - include field
        filtered[field_name] = field_data
      elsif baseline.last_sent_value.to_json != current_value.to_json
        # Value changed - include field
        filtered[field_name] = field_data
      else
        # Value unchanged and not expired - skip field
        Rails.logger.debug("LoopsDispatchWorker: Skipping #{field_name} for #{email_normalized} - unchanged")
      end
    end

    filtered
  end

  # Apply strategies: :upsert (only update if value is not nil), :override (always update)
  def apply_strategies(filtered_payload)
    result = {}

    filtered_payload.each do |field_name, field_data|
      # Handle both string and symbol keys
      field_data_hash = field_data.is_a?(Hash) ? field_data : {}
      strategy = (field_data_hash[:strategy] || field_data_hash["strategy"])&.to_sym || :upsert
      value = field_data_hash[:value] || field_data_hash["value"]

      case strategy
      when :upsert
        # Only include if value is not nil
        if value != nil
          result[field_name] = value
        end
      when :override
        # Always include (even if nil)
        result[field_name] = value
      else
        # Unknown strategy - default to upsert behavior
        if value != nil
          result[field_name] = value
        end
      end
    end

    result
  end
end
