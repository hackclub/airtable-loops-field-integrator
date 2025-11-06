class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # HTTP Basic Authentication for admin routes
  before_action :authenticate_admin

  private

  def authenticate_admin
    username = ENV["ADMIN_USERNAME"]
    password = ENV["ADMIN_PASSWORD"]

    # Only require auth if credentials are configured
    if username.present? && password.present?
      authenticate_or_request_with_http_basic do |u, p|
        u == username && p == password
      end
    end
  end
end
