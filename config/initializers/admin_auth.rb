# Validate that required admin authentication environment variables are set
# Skip during asset precompilation (assets don't need these env vars)
skip_validation = Rails.env.test? || 
                  (defined?(Rake) && Rake.application.top_level_tasks.any? { |task| task.to_s.include?('assets:precompile') }) ||
                  ENV['RAILS_GROUPS'] == 'assets'

unless skip_validation
  required_env_vars = {
    "ADMIN_USERNAME" => ENV["ADMIN_USERNAME"],
    "ADMIN_PASSWORD" => ENV["ADMIN_PASSWORD"]
  }

  missing_vars = required_env_vars.select { |_key, value| value.blank? }.keys

  if missing_vars.any?
    raise <<~ERROR
      Missing required environment variables: #{missing_vars.join(", ")}

      Please set the following environment variables:
      - ADMIN_USERNAME
      - ADMIN_PASSWORD

      For development, you can set both to "test" in docker-compose.yml or your .env file.
    ERROR
  end
end





