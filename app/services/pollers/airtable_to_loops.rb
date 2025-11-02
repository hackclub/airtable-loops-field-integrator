module Pollers
  class AirtableToLoops
    def call(sync_source)
      base_id = sync_source.source_id
      poll_start_time = Time.current.utc
      
      log_header("Processing Airtable Base: #{base_id}")
      
      # Get all tables for the base
      tables = AirtableService::Bases.get_schema(base_id: base_id)
      
      log_info("Found #{tables.size} table(s)")
      
      # Iterate through each table
      tables.each do |table_id, table|
        process_table(sync_source, base_id, table_id, table)
      end
      
      # Update cursor to poll start time after successful processing
      sync_source.update_columns(cursor: poll_start_time.utc.iso8601(3))
      
      log_header("Finished processing base #{base_id}")
    end

    private

    def process_table(sync_source, base_id, table_id, table)
      table_name = table["name"] || table_id
      log_section("Table: #{table_name} (ID: #{table_id})")
      
      # Print schema for debugging
      log_schema(table)
      
      # Validate required fields
      email_field = find_email_field(table)
      unless email_field
        log_info("Skipping table - no 'email' field found")
        return
      end
      
      loops_fields = find_loops_fields(table)
      if loops_fields.empty?
        log_info("Skipping table - no 'Loops - ...' fields found")
        return
      end
      
      log_info("Found email field: #{email_field['name']}")
      log_info("Found #{loops_fields.size} Loops field(s): #{loops_fields.values.map { |f| f['name'] }.join(', ')}")
      
      # Load previously known Loops field IDs from metadata
      metadata = sync_source.metadata || {}
      known_loops_fields = metadata['known_loops_fields'] || {}
      previously_known_field_ids = known_loops_fields[table_id] || []
      
      # Get current Loops field IDs in format "field_id/field_name"
      current_field_ids = loops_fields.map { |field_id, field| field_identifier(field_id, field['name']) }
      
      # Detect if any new Loops fields have been added
      has_new_loops_fields = (current_field_ids - previously_known_field_ids).any?
      
      if has_new_loops_fields
        new_field_ids = current_field_ids - previously_known_field_ids
        log_info("New Loops field(s) detected: #{new_field_ids.join(', ')} - fetching ALL records for this table")
      end
      
      # Build filter formula (skip time filter if new Loops fields detected)
      filter_formula = build_filter_formula(sync_source, email_field, skip_time_filter: has_new_loops_fields)
      
      # Fetch records (fetch all if new Loops fields detected)
      records = fetch_records(base_id, table_id, filter_formula, email_field: email_field, fetch_all: has_new_loops_fields)
      
      if records.empty?
        log_info("No records to process")
        # Still update metadata even if no records
        update_known_loops_fields(sync_source, table_id, current_field_ids)
        return
      end
      
      log_info("Processing #{records.size} record(s) for change detection")
      
      # Detect changed values
      changed_records = detect_changes(sync_source, base_id, table_id, records, loops_fields, email_field)
      
      # Process changed records
      process_changed_records(changed_records, loops_fields)
      
      # Update metadata with current Loops field IDs after processing
      update_known_loops_fields(sync_source, table_id, current_field_ids)
    end

    def find_email_field(table)
      return nil unless table["fields"]
      
      table["fields"].find do |field|
        field_name = field["name"] || ""
        field_name.strip.downcase == "email"
      end
    end

    def find_loops_fields(table)
      return {} unless table["fields"]
      
      loops_pattern = /\ALoops\s*-\s*[a-z][a-zA-Z0-9]*\z/
      
      loops_fields = {}
      table["fields"].each do |field|
        field_name = field["name"] || ""
        if field_name.strip.match?(loops_pattern)
          loops_fields[field["id"]] = field
        end
      end
      
      loops_fields
    end

    # Generate field identifier in format "field_id/field_name" for Airtable fields
    def field_identifier(field_id, field_name)
      "#{field_id}/#{field_name}"
    end

    # Generate row identifier in format "table_id/record_id" for Airtable records
    def row_identifier(table_id, record_id)
      "#{table_id}/#{record_id}"
    end

    def build_filter_formula(sync_source, email_field, skip_time_filter: false)
      conditions = []
      
      # Email validation: matches pattern .+@.+\..+
      # Check: not empty, contains '@', contains '.' after '@', has content before '@'
      email_field_name = email_field["name"]
      # FIND('@', {Email}) > 0 ensures @ exists and there's content before it
      # FIND('.', {Email}, FIND('@', {Email})) ensures . exists after @
      # LEN ensures not empty
      email_condition = "AND(LEN({#{email_field_name}}) > 0, FIND('@', {#{email_field_name}}) > 0, FIND('@', {#{email_field_name}}) < LEN({#{email_field_name}}), FIND('.', {#{email_field_name}}, FIND('@', {#{email_field_name}})) > 0, FIND('.', {#{email_field_name}}, FIND('@', {#{email_field_name}})) < LEN({#{email_field_name}}))"
      conditions << email_condition
      
      # Time-based filtering (if we have a cursor and not skipping time filter)
      unless skip_time_filter
        cursor_timestamp = sync_source.cursor
        if cursor_timestamp
          # Cursor is stored as JSONB string (ISO8601 timestamp)
          # Rails automatically deserializes JSONB strings to Ruby strings
          cursor_time = cursor_timestamp.to_s
          time_condition = "OR(LAST_MODIFIED_TIME() > \"#{cursor_time}\", CREATED_TIME() > \"#{cursor_time}\")"
          conditions << time_condition
        end
      end
      
      # Combine all conditions with AND
      if conditions.size > 1
        "AND(#{conditions.join(', ')})"
      elsif conditions.size == 1
        conditions.first
      else
        email_condition # fallback to just email check
      end
    end

    def fetch_records(base_id, table_id, filter_formula, email_field: nil, fetch_all: false)
      # Always use pagination to handle all cases (with or without filter_formula)
      # Airtable's offset-based pagination is safe for preventing race conditions
      # The offset token provided by Airtable is stable and handles concurrent changes
      records = []
      
      begin
        if fetch_all
          # When fetching all records, we don't use filter_formula (skip time filter)
          # Apply email validation filter manually since we're fetching everything
          AirtableService::Records.find_each(base_id: base_id, table_id: table_id) do |record|
            record_fields = record["fields"] || {}
            
            if email_field
              email_value = record_fields[email_field["name"]]
              # Validate email pattern: .+@.+\..+ (same pattern as in build_filter_formula)
              if email_value && email_value.to_s =~ /.+@.+\..+/
                records << record
              end
            else
              # If no email field provided, include all records (shouldn't happen in practice)
              records << record
            end
          end
        else
          # Use filter_formula (includes email validation and time filter if applicable)
          # Pagination will handle cases where filter_formula returns more than 100 records
          AirtableService::Records.find_each(
            base_id: base_id,
            table_id: table_id,
            filter_formula: filter_formula
          ) do |record|
            records << record
          end
        end
        
        records
      rescue => e
        log_error("Error fetching records: #{e.class.name} - #{e.message}")
        []
      end
    end

    def detect_changes(sync_source, base_id, table_id, records, loops_fields, email_field)
      changed_records = []
      
      records.each do |record|
        record_id = record["id"]
        row_id = row_identifier(table_id, record_id)
        record_fields = record["fields"] || {}
        changed_values = {}
        
        loops_fields.each do |field_id, field|
          current_value = record_fields[field["name"]]
          
          # Use format "field_id/field_name" for field identification
          field_id_key = field_identifier(field_id, field['name'])
          
          result = FieldValueBaseline.detect_change(
            sync_source: sync_source,
            row_id: row_id,
            field_id: field_id_key,
            current_value: current_value
          )
          
          if result[:changed]
            changed_values[field_id_key] = current_value
          end
        end
        
        unless changed_values.empty?
          email = record_fields[email_field["name"]]
          changed_records << {
            id: record_id,
            email: email,
            changedValues: changed_values
          }
        end
      end
      
      changed_records
    end

    def process_changed_records(changed_records, loops_fields)
      if changed_records.empty?
        log_info("No changed records found")
        return
      end
      
      log_info("Found #{changed_records.size} record(s) with changes")
      
      changed_records.each do |changed_record|
        puts "\nChanged Record:"
        puts "  ID: #{changed_record[:id]}"
        puts "  Email: #{changed_record[:email].inspect}" if changed_record[:email]
        puts "  Changed Values:"
        changed_record[:changedValues].each do |field_identifier, value|
          # Parse field_identifier which is in format "field_id/field_name"
          field_id, field_name = field_identifier.split('/', 2)
          field = loops_fields[field_id]
          
          if field
            # Strip "Loops - " prefix if present
            display_name = field_name.sub(/\ALoops\s*-\s*/i, "")
            puts "    #{display_name.inspect} -> #{value.inspect}"
          else
            # Fallback to field_identifier if field not found
            puts "    #{field_identifier}: #{value.inspect}"
          end
        end
      end
    end

    # Logging helpers
    def log_header(message)
      puts "\n=== #{message} ===\n"
    end

    def log_section(message)
      puts "\n" + "=" * 80
      puts message
      puts "=" * 80
    end

    def log_info(message)
      puts message
    end

    def log_error(message)
      puts "ERROR: #{message}"
    end

    def log_schema(table)
      puts "\nSchema:"
      puts "-" * 80
      puts "Fields:"
      if table["fields"] && table["fields"].any?
        table["fields"].each do |field|
          field_type = field["type"] || "unknown"
          field_name = field["name"] || field["id"]
          puts "  - #{field_name} (#{field_type})"
        end
      else
        puts "  (no fields found)"
      end
    end

    def update_known_loops_fields(sync_source, table_id, current_field_ids)
      # Update metadata to store current Loops field IDs for this table
      metadata = sync_source.metadata || {}
      metadata['known_loops_fields'] ||= {}
      metadata['known_loops_fields'][table_id] = current_field_ids
      sync_source.update_columns(metadata: metadata)
    end
  end
end
