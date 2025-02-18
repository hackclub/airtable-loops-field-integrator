GoodJob::Engine.middleware.use(Rack::Auth::Basic) do |username, password|
  ActiveSupport::SecurityUtils.secure_compare(Rails.application.credentials.good_job.username, username) &
    ActiveSupport::SecurityUtils.secure_compare(Rails.application.credentials.good_job.password, password)
end