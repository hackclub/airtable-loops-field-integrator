module Pollers
  class AirtableToLoops
    def call(sync_source)
      base_id = sync_source.source_id
      
      puts "\n=== Processing Airtable Base: #{base_id} ===\n"
      
      # Get all tables for the base
      tables = AirtableService::Bases.get_schema(base_id: base_id)
      
      puts "Found #{tables.size} table(s)\n\n"
      
      # Iterate through each table
      tables.each do |table_id, table|
        table_name = table["name"] || table_id
        puts "\n" + "=" * 80
        puts "Table: #{table_name} (ID: #{table_id})"
        puts "=" * 80
        
        # Print schema
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
        
        # Build filter formula using Airtable formula functions
        # We can use LAST_MODIFIED_TIME() and CREATED_TIME() directly in filter formulas
        filter_formula = nil
        last_poll_time = nil
        
        if sync_source.last_successful_poll_at
          last_poll_time = sync_source.last_successful_poll_at.utc.iso8601(3)
          # Use OR formula to filter by either created OR modified time
          # Format: OR(LAST_MODIFIED_TIME() > "timestamp", CREATED_TIME() > "timestamp")
          filter_formula = "OR(LAST_MODIFIED_TIME() > \"#{last_poll_time}\", CREATED_TIME() > \"#{last_poll_time}\")"
          
          puts "\nTime tracking (using formula functions):"
          puts "  Filter: records where CREATED_TIME() OR LAST_MODIFIED_TIME() > #{last_poll_time}"
        else
          puts "\nTime tracking:"
          puts "  (no previous poll time - will fetch all records)"
        end
        
        # Fetch records using filter formula
        puts "\nFetching records:"
        puts "-" * 80
        begin
          response = AirtableService::Records.list(
            base_id: base_id,
            table_id: table_id,
            max_records: 100,
            filter_formula: filter_formula
          )
          
          records = response["records"] || []
          puts "  Fetched #{records.size} records"
          if filter_formula
            puts "  Using filter: #{filter_formula}"
          end
          
          # Display first 3 records for debugging
          display_records = records.first(3)
          puts "\nDisplaying first #{display_records.size} of #{records.size} records:"
          
          if display_records.empty?
            puts "  (no records found)"
          else
            display_records.each_with_index do |record, index|
              puts "\n  Record #{index + 1}:"
              puts "    ID: #{record['id']}"
              puts "    Created: #{record['createdTime']}" if record['createdTime']
              
              # Check if fields exist and have values
              fields = record["fields"]
              puts "    Fields:"
              if fields.nil?
                puts "      (fields key missing)"
              elsif fields.respond_to?(:empty?) && fields.empty?
                puts "      (fields empty)"
              elsif fields.is_a?(Hash) && fields.any?
                fields.each do |field_name, field_value|
                  # Handle nil values
                  if field_value.nil?
                    puts "      #{field_name}: (nil)"
                  else
                    # Truncate long values for readability
                    display_value = case field_value
                    when String
                      field_value.length > 50 ? "#{field_value[0..47]}..." : field_value
                    when Array
                      if field_value.size > 3
                        "#{field_value[0..2].inspect}... (#{field_value.size} items)"
                      else
                        field_value.inspect
                      end
                    when Hash
                      field_value.inspect.length > 50 ? "#{field_value.inspect[0..47]}..." : field_value.inspect
                    else
                      field_value.to_s.length > 50 ? "#{field_value.to_s[0..47]}..." : field_value.to_s
                    end
                    puts "      #{field_name}: #{display_value}"
                  end
                end
              else
                puts "      (unexpected fields type: #{fields.class})"
              end
            end
          end
        rescue => e
          puts "  Error fetching records: #{e.class.name} - #{e.message}"
        end
        
        puts "\n"
      end
      
      puts "\n=== Finished processing base #{base_id} ===\n"
    end

    private
  end
end
