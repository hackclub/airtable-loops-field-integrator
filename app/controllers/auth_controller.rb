class AuthController < ApplicationController
  skip_before_action :authenticate_admin

  def show_otp_request
    # Check if user is already authenticated
    token = session[:auth_token]
    email = AuthenticationService.validate_session(token)
    
    if email
      # Already authenticated, redirect to profile edit
      redirect_to profile_edit_path
      return
    end
    
    # Not authenticated, show OTP request form
  end

  def request_otp
    email = params[:email]&.strip

    if email.blank?
      flash[:error] = "Email is required"
      redirect_to auth_otp_request_path
      return
    end

    begin
      code = AuthenticationService.generate_otp(email)

      # Send OTP via Loops transactional email
      transactional_id = ENV.fetch("LOOPS_OTP_TRANSACTIONAL_ID")
      LoopsService.send_transactional_email(
        email: email,
        transactional_id: transactional_id,
        data_variables: { otp_code: code }
      )

      # Store email in session for verification step
      session[:otp_email] = email

      flash[:notice] = "OTP code sent to your email. Please check your inbox."
      redirect_to auth_otp_verify_path
    rescue AuthenticationService::RateLimitExceeded => e
      flash[:error] = e.message
      redirect_to auth_otp_request_path
    rescue => e
      Rails.logger.error("AuthController#request_otp error: #{e.class} - #{e.message}")
      flash[:error] = "Failed to send OTP. Please try again."
      redirect_to auth_otp_request_path
    end
  end

  def show_verify_otp
    # Show OTP verification form
    @email = session[:otp_email]
    redirect_to auth_otp_request_path if @email.blank?
  end

  def verify_otp
    email = session[:otp_email]
    code = params[:code]&.strip

    if email.blank?
      flash[:error] = "Session expired. Please request a new OTP."
      redirect_to auth_otp_request_path
      return
    end

    if code.blank?
      flash[:error] = "OTP code is required"
      redirect_to auth_otp_verify_path
      return
    end

    begin
      AuthenticationService.verify_otp(email, code)

      # Rotate session to prevent fixation attacks
      reset_session

      # Create authenticated session
      token = AuthenticationService.create_session(email)

      # Store token in session cookie (after reset_session)
      session[:auth_token] = token

      flash[:notice] = "Successfully authenticated!"
      redirect_to profile_edit_path
    rescue AuthenticationService::InvalidOtp, AuthenticationService::OtpExpired, AuthenticationService::OtpAlreadyVerified => e
      flash[:error] = e.message
      redirect_to auth_otp_verify_path
    rescue => e
      Rails.logger.error("AuthController#verify_otp error: #{e.class} - #{e.message}")
      flash[:error] = "Failed to verify OTP. Please try again."
      redirect_to auth_otp_verify_path
    end
  end
end

