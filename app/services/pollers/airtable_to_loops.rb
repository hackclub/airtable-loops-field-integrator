module Pollers
  class AirtableToLoops
    def call(sync_source)
      base_id = sync_source.source_id
      
      log_header("Processing Airtable Base: #{base_id}")
      
      # Get all tables for the base
      tables = AirtableService::Bases.get_schema(base_id: base_id)
      
      log_info("Found #{tables.size} table(s)")
      
      # Iterate through each table
      tables.each do |table_id, table|
        process_table(sync_source, base_id, table_id, table)
      end
      
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
      
      # Build filter formula
      filter_formula = build_filter_formula(sync_source, email_field)
      
      # Fetch records
      records = fetch_records(base_id, table_id, filter_formula)
      
      if records.empty?
        log_info("No records to process")
        return
      end
      
      log_info("Processing #{records.size} record(s) for change detection")
      
      # Detect changed values
      changed_records = detect_changes(sync_source, base_id, table_id, records, loops_fields, email_field)
      
      # Process changed records
      process_changed_records(changed_records, loops_fields)
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

    def build_filter_formula(sync_source, email_field)
      conditions = []
      
      # Email validation: matches pattern .+@.+\..+
      # Check: not empty, contains '@', contains '.' after '@', has content before '@'
      email_field_name = email_field["name"]
      # FIND('@', {Email}) > 0 ensures @ exists and there's content before it
      # FIND('.', {Email}, FIND('@', {Email})) ensures . exists after @
      # LEN ensures not empty
      email_condition = "AND(LEN({#{email_field_name}}) > 0, FIND('@', {#{email_field_name}}) > 0, FIND('@', {#{email_field_name}}) < LEN({#{email_field_name}}), FIND('.', {#{email_field_name}}, FIND('@', {#{email_field_name}})) > 0, FIND('.', {#{email_field_name}}, FIND('@', {#{email_field_name}})) < LEN({#{email_field_name}}))"
      conditions << email_condition
      
      # Time-based filtering (if we have a last poll time)
      if sync_source.last_successful_poll_at
        last_poll_time = sync_source.last_successful_poll_at.utc.iso8601(3)
        time_condition = "OR(LAST_MODIFIED_TIME() > \"#{last_poll_time}\", CREATED_TIME() > \"#{last_poll_time}\")"
        conditions << time_condition
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

    def fetch_records(base_id, table_id, filter_formula)
      response = AirtableService::Records.list(
        base_id: base_id,
        table_id: table_id,
        max_records: 100,
        filter_formula: filter_formula
      )
      
      response["records"] || []
    rescue => e
      log_error("Error fetching records: #{e.class.name} - #{e.message}")
      []
    end

    def detect_changes(sync_source, base_id, table_id, records, loops_fields, email_field)
      changed_records = []
      
      records.each do |record|
        record_id = record["id"]
        row_id = "#{table_id}/#{record_id}"
        record_fields = record["fields"] || {}
        changed_values = {}
        
        loops_fields.each do |field_id, field|
          current_value = record_fields[field["name"]]
          
          result = FieldValueBaseline.detect_change(
            sync_source: sync_source,
            row_id: row_id,
            field_id: field_id,
            current_value: current_value
          )
          
          if result[:changed]
            changed_values[field_id] = current_value
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
        changed_record[:changedValues].each do |field_id, value|
          field = loops_fields[field_id]
          if field
            field_name = field["name"] || field_id
            # Strip "Loops - " prefix if present
            display_name = field_name.sub(/\ALoops\s*-\s*/i, "")
            puts "    #{display_name.inspect} -> #{value.inspect}"
          else
            # Fallback to field_id if field not found
            puts "    #{field_id}: #{value.inspect}"
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
  end
end
