ENV["RAILS_ENV"] ||= "test"

# Ensure tests use the test database, not the development database
# Override DATABASE_URL to point to test database if not already pointing to a test DB
if ENV["DATABASE_URL"] && !ENV["DATABASE_URL"].include?("_test") && !ENV["TEST_DATABASE_URL"]
  # Extract connection details from existing DATABASE_URL
  # Format: postgresql://user:pass@host:port/dbname
  db_url = ENV["DATABASE_URL"]

  # Parse the URL to extract components
  if db_url.match(%r{postgresql?://([^:]+):([^@]+)@([^:/]+):?(\d+)?/(.+)})
    db_user = $1
    db_pass = $2
    db_host = $3
    db_port = $4 || "5432"
    db_name = $5

    # Replace database name with test database name
    test_db_name = ENV.fetch("TEST_DB_NAME", "app_test")
    ENV["DATABASE_URL"] = "postgresql://#{db_user}:#{db_pass}@#{db_host}:#{db_port}/#{test_db_name}"
  else
    # Fallback: use environment variables or defaults
    db_host = ENV.fetch("DB_HOST", "db")
    db_user = ENV.fetch("DB_USERNAME", "postgres")
    db_pass = ENV.fetch("DB_PASSWORD", "postgres")
    db_port = ENV.fetch("DB_PORT", "5432")
    test_db_name = ENV.fetch("TEST_DB_NAME", "app_test")
    ENV["DATABASE_URL"] = "postgresql://#{db_user}:#{db_pass}@#{db_host}:#{db_port}/#{test_db_name}"
  end
end

require_relative "../config/environment"

# Ensure test database exists before requiring rails/test_help
# This allows Rails to automatically create and setup the test database
begin
  # Get database config
  db_config = ActiveRecord::Base.configurations.configs_for(env_name: "test").first

  # Try to establish connection - will fail if database doesn't exist
  ActiveRecord::Base.establish_connection(db_config.configuration_hash)
  ActiveRecord::Base.connection.execute("SELECT 1")
rescue ActiveRecord::NoDatabaseError, PG::ConnectionBad => e
  # Database doesn't exist - create it using Rails database tasks
  begin
    ActiveRecord::Tasks::DatabaseTasks.env = "test"
    ActiveRecord::Tasks::DatabaseTasks.create_current
  rescue => create_error
    # If Rails tasks fail, try direct PostgreSQL connection
    begin
      require "pg"
      config_hash = db_config.configuration_hash
      # Connect to 'postgres' database to create the test database
      conn = PG.connect(
        host: config_hash["host"] || config_hash[:host] || "db",
        port: config_hash["port"] || config_hash[:port] || 5432,
        user: config_hash["username"] || config_hash[:username] || "postgres",
        password: config_hash["password"] || config_hash[:password] || "postgres",
        dbname: "postgres"
      )
      conn.exec("CREATE DATABASE #{db_config.database}")
      conn.close
    rescue => pg_error
      # If all else fails, let Rails handle it and show a warning
      puts "Warning: Could not auto-create test database: #{pg_error.message}"
    end
  end

  # Reconnect to the newly created database
  ActiveRecord::Base.establish_connection(db_config.configuration_hash)
rescue => e
  # Other errors - let Rails handle them
  puts "Warning: Database connection issue: #{e.message}"
end

require "rails/test_help"

# Global safety net: Prevent accidental real email sends in tests
# Individual tests should still stub LoopsService.send_transactional_email explicitly
# when testing email behavior, but this prevents real emails if a test forgets to stub it
if defined?(LoopsService)
  LoopsService.define_singleton_method(:send_transactional_email) do |*args|
    # In test environment, default to stubbing email sends to prevent real emails
    # Tests can override this by explicitly stubbing the method (minitest stubs will take precedence)
    { "success" => true, "test_stub" => true }
  end
end

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
