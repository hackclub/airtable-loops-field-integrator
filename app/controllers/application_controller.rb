class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # HTTP Basic Authentication for admin routes
  before_action :authenticate_admin

  # Make current_authenticated_email available to views
  helper_method :current_authenticated_email

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

  def require_authenticated_session
    token = session[:auth_token]
    email = AuthenticationService.validate_session(token)

    unless email
      flash[:error] = "Please authenticate to continue"
      # Preserve the current path as redirect destination after authentication
      session[:redirect_after_auth] = request.path
      redirect_to auth_otp_request_path
      return
    end

    @current_authenticated_email = email
  end

  def current_authenticated_email
    @current_authenticated_email ||= begin
      token = session[:auth_token]
      AuthenticationService.validate_session(token)
    end
  end
end
