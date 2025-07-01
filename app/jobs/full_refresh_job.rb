class FullRefreshJob < ApplicationJob
  LOOPS_FIELD_REGEX = /^Loops - (?<loops_field_name>[^\s]+)$/
  LOOPS_SPECIAL_FIELD_REGEX = /^Loops - Special - (?<special_field_name>setFullName|setFullAddress)$/

  class MissingEmailFieldError < StandardError
    def initialize(table_id)
      super("Table #{table_id} must have a field titled 'Email'")
    end
  end

  class InvalidEmailFormatError < StandardError
    def initialize(email)
      super("Invalid email format for \"#{email}\"")
    end
  end

  class InvalidSpecialFieldError < StandardError
    def initialize(special_field_name)
      super("Invalid special field name: \"#{special_field_name}\"")
    end
  end

  retry_on AirtableService::RateLimitError, AirtableService::TimeoutError, wait: :polynomially_longer, attempts: Float::INFINITY

  def perform(base_id)
    Rails.logger.info "Starting full refresh for base #{base_id}"
    
    # Get the schema for all tables in the base
    schema = AirtableService::Bases.get_cached_schema(base_id: base_id)
    timestamp = Time.current
    
    # Process each table
    schema.each do |table_id, table_data|
      process_table(base_id, table_id, table_data, timestamp)
    end
    
    Rails.logger.info "Completed full refresh for base #{base_id}"
  end

  private

  def process_table(base_id, table_id, table_data, timestamp)
    fields = table_data['fields']
    
    # Check if this table has any Loops fields
    loops_fields = fields.select do |field|
      field["name"].match(LOOPS_FIELD_REGEX) || field["name"].match(LOOPS_SPECIAL_FIELD_REGEX)
    end
    
    return if loops_fields.empty?
    
    # Check for email field
    email_field = fields.find { |f| f['name'].downcase == 'email' }
    raise MissingEmailFieldError.new(table_id) unless email_field
    
    Rails.logger.info "Processing table #{table_id} with #{loops_fields.size} Loops fields"
    
    # Process all records in this table
    AirtableService::Records.find_each(base_id: base_id, table_id: table_id) do |record|
      process_record(base_id, record, fields, email_field, timestamp)
    end
  end

  def process_record(base_id, record, fields, email_field, timestamp)
    record_id = record['id']
    field_values = record['fields'] || {}
    
    # Get email value
    email_value = field_values[email_field['name']]
    return unless email_value && valid_email?(email_value)
    
    loops_field_updates = {}
    
    # Check each field in the record
    field_values.each do |field_name, value|
      field = fields.find { |f| f['name'] == field_name }
      next unless field
      
      normal_match = field["name"].match(LOOPS_FIELD_REGEX)
      special_match = field["name"].match(LOOPS_SPECIAL_FIELD_REGEX)
      next unless normal_match || special_match
      
      if normal_match
        loops_field_name = normal_match[:loops_field_name]
        loops_field_updates[loops_field_name] = value
      elsif special_match
        special_field_name = special_match[:special_field_name]
        
        case special_field_name
        when 'setFullName'
          LoopsSpecialSetFullNameJob.set(priority: timestamp.to_i).perform_later(timestamp, base_id, email_value, value)
        when 'setFullAddress'
          LoopsSpecialSetFullAddressJob.set(priority: timestamp.to_i).perform_later(timestamp, base_id, email_value, value)
        else
          raise InvalidSpecialFieldError.new(special_field_name)
        end
      end
    end
    
    if loops_field_updates.any?
      priority = timestamp.to_i
      if ENV.fetch('PRIORITY_BASES', '').split(',').include?(base_id)
        priority = 0
      end
      LoopsUpdateFieldJob.set(priority: priority).perform_later(base_id, email_value, loops_field_updates)
    end
    
  rescue InvalidEmailFormatError => e
    Rails.logger.warn "Skipping record #{record_id}: #{e.message}"
  end

  def valid_email?(email)
    return false unless email.is_a?(String)
    return false unless EmailValidator.valid?(email, mode: :strict)
    return false unless email.ascii_only?
    
    # Check if TLD has more than one character
    domain = email.split('@')[1]
    tld = domain&.split('.')&.last
    return false unless tld && tld.length > 1
    
    true
  end
end
