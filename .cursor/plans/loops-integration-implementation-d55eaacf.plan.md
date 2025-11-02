<!-- d55eaacf-b680-4a95-9479-1bad3327be24 681e5975-e11f-49f9-bca3-533c081408d0 -->
# Loops Integration Implementation Plan

## Overview

Implement end-to-end Loops integration: detect Airtable changes → normalize email → queue job → fan-in by email → AI transforms → write outbox → dispatch → baseline filtering → send → audit.

## Implementation Steps

### 1. Database Schema (3 migrations)

- **`loops_outbox_envelopes`**: id, email_normalized (string), payload (jsonb), status (enum: queued/sent/ignored_noop/failed/partially_sent), provenance (jsonb), error (jsonb), created_at, updated_at. Index on (email_normalized, status) for batching.
- **`loops_field_baselines`**: id, email_normalized (string), field_name (string), last_sent_value (jsonb), last_sent_at (datetime), expires_at (datetime), created_at, updated_at. Unique index on (email_normalized, field_name).
- **`loops_contact_change_audits`**: id, occurred_at (datetime), email_normalized (string), field_name (string), former_loops_value (jsonb), new_loops_value (jsonb), former_airtable_value (jsonb), new_airtable_value (jsonb), strategy (string), sync_source_id (bigint), table_id (string), record_id (string), airtable_field_id (string), request_id (string). Indexes on email_normalized, occurred_at, sync_source_id.

### 2. Models (3 new models)

- **`LoopsOutboxEnvelope`**: belongs_to :sync_source (optional), validations, scopes for queued/sent/failed, status enum (queued/sent/ignored_noop/failed/partially_sent).
- **`LoopsFieldBaseline`**: validations, scope for expired, class method to find/update baseline.
- **`LoopsContactChangeAudit`**: belongs_to :sync_source, validations, scopes for querying.

### 3. Email Normalization Helper

- Extract `normalize_email` from `LoopsService` to shared module `EmailNormalizer` (app/lib/email_normalizer.rb).
- Update `LoopsService` to use the shared helper.
- Helper: lowercase + strip whitespace, handles nil/empty.

### 4. PrepareLoopsFieldsForOutbox Job

- **Location**: `app/jobs/prepare_loops_fields_for_outbox_job.rb`
- **Input**: email (raw), sync_source_id, table_id, record_id, changed_fields hash (field_id → {value, modified_at, old_value}).
- **Logic**:
- Normalize email, return early if blank/invalid.
- Acquire per-email advisory lock (hash email to integer using Digest::SHA256, use namespace constant like `SyncSourcePollWorker`).
- **AI Transform Stub**: TODO comment with sample response format documented. Placeholder method that returns fields unchanged for now.
- **Field Name Mapping Stub**: TODO comment - currently strip "Loops - " prefix (to be implemented properly later).
- **Determine strategies inside job**: For each field, determine strategy (:upsert or :override). Strategy logic to be implemented later (scaffold for now, default :upsert).
- Build envelope: `{field_name => {value, strategy, type, modified_at}}`.
- **Use old/new values passed in** (from changed_fields hash) for provenance - don't read from FieldValueBaseline as it may have already updated.
- Write to `loops_outbox_envelopes` with status=queued, payload=envelope, provenance (self-contained jsonb with sync_source_id, table_id, record_id, fields array with airtable_field_id, airtable_old_value, airtable_new_value, modified_at, created_from="airtable_poller").
- Release lock.

### 5. LoopsDispatchWorker

- **Location**: `app/workers/loops_dispatch_worker.rb`
- **Queue**: `:default`
- **Concurrency**: Multiple workers can run simultaneously. Use advisory locks per email to prevent conflicts. Each worker processes different emails (lock contention only happens for same email).
- **Logic**:
- Batch envelopes by email (find all `queued` status, group by email_normalized). Use `FOR UPDATE SKIP LOCKED` to allow multiple workers to process different emails concurrently.
- For each email:
- Acquire per-email advisory lock (same hash approach as job).
- Load all queued envelopes for that email.
- Merge envelopes: combine payloads, latest `modified_at` wins per field.
- Filter by `loops_field_baselines`: compare each field value to baseline (AFTER merging), drop if equal and not expired.
- If anything remains:
- Call `LoopsService.update_contact` with merged payload (LoopsService handles rate limiting internally).
- **Implement strategy logic**: :upsert (only update if value is not nil), :override (update no matter what).
- In DB transaction:
- Update/create `loops_field_baselines` for each sent field (set expires_at = now + 90 days).
- Insert `loops_contact_change_audits` rows (one per field that was sent).
- Mark envelopes as `sent` (if all fields sent), `partially_sent` (if some fields sent, some filtered), or `ignored_noop` (if nothing sent).
- On API failure: mark envelopes `failed`, store error in `error` jsonb, implement retry policy.
- Release lock.

### 6. Update Poller to Enqueue Job

- Modify `Pollers::AirtableToLoops#process_changed_records`:
- For each changed record, extract email and normalize.
- Build changed_fields hash with field_id → {value, modified_at, old_value from baseline} (read baseline BEFORE it updates).
- Call `PrepareLoopsFieldsForOutboxJob.perform_async` with email, sync_source_id, table_id, record_id, changed_fields hash (no strategies hash).

### 7. Pruning Workers (2 workers)

- **`PruneLoopsFieldBaselinesWorker`**: Similar to `PruneFieldValueBaselinesWorker`, prune rows where `expires_at < Time.current` (90-day TTL).
- **`PruneLoopsOutboxWorker`**: Delete `sent/ignored_noop/failed/partially_sent` envelopes older than retention period (e.g., 30 days).
- **Add both to Sidekiq schedule** in `config/sidekiq.yml` under `:schedule:` section.

### 8. LoopsService Enhancement

- **Implement strategy logic in `update_contact`**: 
- If field has strategy `:upsert`: only include field in API call if value is not nil.
- If field has strategy `:override`: include field in API call regardless of value.
- Pass fields with their strategies to Loops API appropriately.

### 9. Testing Considerations

- Unit tests for models, job, worker, helpers.
- Integration tests for full flow.
- Advisory lock tests (similar to `SyncSourcePollWorkerTest`).
- Test partial send scenarios.

## Key Design Decisions

- Per-email advisory locks prevent race conditions (hash email to integer).
- Outbox pattern ensures durability.
- Baseline filtering happens AFTER merging payloads (more efficient).
- Multiple dispatch workers can run concurrently (different emails processed in parallel).
- Rate limiting handled by LoopsService internally (no need to acquire in worker).
- Strategy logic implemented real: :upsert (skip nil), :override (always send).
- Partial sends tracked with `partially_sent` status.
- Dual provenance strategy:
- **Outbox envelope provenance** (self-contained jsonb): Stores sync_source_id, table_id, record_id, and per-field airtable context (airtable_field_id, airtable_old_value, airtable_new_value, modified_at). Makes envelopes debuggable without joins.
- **Audit table** (`loops_contact_change_audits`): One row per field actually sent to Loops. Stores full bidirectional tracking with proper indexes.
- Old/new values passed into job (not read from baseline) to avoid race conditions.
- Strategies determined inside PrepareLoopsFieldsForOutbox job, not passed in.

### To-dos

- [ ] Create 3 database migrations for loops_outbox_envelopes, loops_field_baselines, and loops_contact_change_audits tables
- [ ] Create 3 ActiveRecord models: LoopsOutboxEnvelope, LoopsFieldBaseline, LoopsContactChangeAudit with validations and associations
- [ ] Extract normalize_email to shared EmailNormalizer module and update LoopsService to use it
- [ ] Create PrepareLoopsFieldsForOutboxJob with per-email advisory locking, AI transform stubs, envelope building, and outbox writing
- [ ] Create LoopsDispatchWorker with batching, merging, baseline filtering, rate limiting, Loops API calls, and atomic updates
- [ ] Update Pollers::AirtableToLoops#process_changed_records to enqueue PrepareLoopsFieldsForOutboxJob
- [ ] Create PruneLoopsFieldBaselinesWorker and PruneLoopsOutboxWorker for cleanup
- [ ] Enhance LoopsService.update_contact to handle field strategies if needed