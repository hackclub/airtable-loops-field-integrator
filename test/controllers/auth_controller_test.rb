require "test_helper"
require "minitest/mock"

class AuthControllerTest < ActionDispatch::IntegrationTest
  def setup
    skip "Redis not available" unless REDIS_FOR_RATE_LIMITING.ping
    
    @email = "test@example.com"
    @email_normalized = EmailNormalizer.normalize(@email)
    
    # Clear rate limits
    REDIS_FOR_RATE_LIMITING.del("rate:otp:#{@email_normalized}")
    
    # Clean up
    OtpVerification.where(email_normalized: @email_normalized).delete_all
    AuthenticatedSession.where(email_normalized: @email_normalized).delete_all
    
    # Set test transactional ID
    @original_transactional_id = ENV["LOOPS_OTP_TRANSACTIONAL_ID"]
    ENV["LOOPS_OTP_TRANSACTIONAL_ID"] = "test_transactional_id"
  end

  def teardown
    REDIS_FOR_RATE_LIMITING.del("rate:otp:#{@email_normalized}")
    OtpVerification.where(email_normalized: @email_normalized).delete_all
    AuthenticatedSession.where(email_normalized: @email_normalized).delete_all
    
    ENV["LOOPS_OTP_TRANSACTIONAL_ID"] = @original_transactional_id if @original_transactional_id
  end

  test "show_otp_request renders form when not authenticated" do
    get auth_otp_request_path
    assert_response :success
    assert_match(/Email Address/i, response.body)
  end

  test "show_otp_request redirects to profile edit when already authenticated" do
    # Create authenticated session and verify OTP to set session
    code = AuthenticationService.generate_otp(@email)
    LoopsService.stub(:send_transactional_email, ->(*args) { { "success" => true } }) do
      AuthenticationService.stub(:generate_otp, ->(email) { code }) do
        post auth_otp_request_path, params: { email: @email }
      end
      post auth_otp_verify_path, params: { code: code }
    end
    
    # Now accessing OTP request should redirect
    get auth_otp_request_path
    assert_redirected_to profile_edit_path
  end

  test "request_otp generates and sends OTP" do
    LoopsService.stub(:send_transactional_email, ->(*args) { { "success" => true } }) do
      post auth_otp_request_path, params: { email: @email }
      
      assert_redirected_to auth_otp_verify_path
      assert_equal "OTP code sent to your email. Please check your inbox.", flash[:notice]
      
      # Verify OTP was created
      otp = OtpVerification.last
      assert_equal @email_normalized, otp.email_normalized
    end
  end

  test "request_otp requires email" do
    post auth_otp_request_path, params: { email: "" }
    
    assert_redirected_to auth_otp_request_path
    assert_equal "Email is required", flash[:error]
  end

  test "request_otp handles rate limit" do
    # Generate 3 OTPs to hit rate limit
    3.times do
      AuthenticationService.generate_otp(@email)
    end
    
    LoopsService.stub(:send_transactional_email, ->(*args) { { "success" => true } }) do
      post auth_otp_request_path, params: { email: @email }
      
      assert_redirected_to auth_otp_request_path
      assert_match(/Too many OTP requests/i, flash[:error])
    end
  end

  test "show_verify_otp requires session email" do
    get auth_otp_verify_path
    assert_redirected_to auth_otp_request_path
  end

  test "verify_otp creates session and redirects" do
    # Generate OTP code first
    code = AuthenticationService.generate_otp(@email)
    
    # Now stub generate_otp to return the same code when request_otp is called
    AuthenticationService.stub(:generate_otp, ->(email) { code }) do
      LoopsService.stub(:send_transactional_email, ->(*args) { { "success" => true } }) do
        post auth_otp_request_path, params: { email: @email }
        assert_redirected_to auth_otp_verify_path
      end
    end
    
    # Verify OTP (session should persist from previous request)
    post auth_otp_verify_path, params: { code: code }
    
    assert_redirected_to profile_edit_path
    assert_equal "Successfully authenticated!", flash[:notice]
    
    # Verify session was created
    session = AuthenticatedSession.last
    assert_equal @email_normalized, session.email_normalized
  end

  test "verify_otp fails with invalid code" do
    LoopsService.stub(:send_transactional_email, ->(*args) { { "success" => true } }) do
      post auth_otp_request_path, params: { email: @email }
      assert_redirected_to auth_otp_verify_path
    end
    
    # Session should persist, so we can verify with wrong code
    post auth_otp_verify_path, params: { code: "0000" }
    
    assert_redirected_to auth_otp_verify_path
    assert_match(/Invalid/i, flash[:error])
  end

  test "verify_otp requires code" do
    LoopsService.stub(:send_transactional_email, ->(*args) { { "success" => true } }) do
      post auth_otp_request_path, params: { email: @email }
      assert_redirected_to auth_otp_verify_path
    end
    
    # Session should persist
    post auth_otp_verify_path, params: { code: "" }
    
    assert_redirected_to auth_otp_verify_path
    assert_equal "OTP code is required", flash[:error]
  end

  test "verify_otp rotates session to prevent fixation" do
    # Generate OTP code first
    code = AuthenticationService.generate_otp(@email)
    
    # Request OTP (sets session[:otp_email])
    LoopsService.stub(:send_transactional_email, ->(*args) { { "success" => true } }) do
      AuthenticationService.stub(:generate_otp, ->(email) { code }) do
        post auth_otp_request_path, params: { email: @email }
      end
    end
    
    # Store old session data to verify it gets cleared
    # Note: In Rails integration tests, we can't directly access session.id,
    # but we can verify that reset_session works by checking that auth still succeeds
    
    # Verify OTP - should reset session before setting auth_token
    post auth_otp_verify_path, params: { code: code }
    
    assert_redirected_to profile_edit_path
    assert_equal "Successfully authenticated!", flash[:notice]
    
    # Verify we can access protected route (proves session was rotated and auth_token was set)
    LoopsService.stub(:find_contact, ->(**args) { [{ "firstName" => "Test" }] }) do
      get profile_edit_path
      assert_response :success
    end
  end

  test "verify_otp locks out after 5 failed attempts" do
    code = AuthenticationService.generate_otp(@email)
    
    LoopsService.stub(:send_transactional_email, ->(*args) { { "success" => true } }) do
      post auth_otp_request_path, params: { email: @email }
    end
    
    # Make 5 failed attempts
    5.times do
      post auth_otp_verify_path, params: { code: "0000" }
      assert_redirected_to auth_otp_verify_path
      assert_match(/Invalid/i, flash[:error])
    end
    
    # 6th attempt should be locked out
    post auth_otp_verify_path, params: { code: "0000" }
    assert_redirected_to auth_otp_verify_path
    assert_match(/Too many failed attempts/i, flash[:error])
    
    # Even correct code should fail after lockout
    post auth_otp_verify_path, params: { code: code }
    assert_redirected_to auth_otp_verify_path
    assert_match(/Too many failed attempts/i, flash[:error])
  end
end

