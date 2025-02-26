module Api
  class BaseController < ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :authenticate_request

    private

    def authenticate_request
      authenticate_with_http_token do |token, _options|
        if token.present? && ActiveSupport::SecurityUtils.secure_compare(token, Rails.application.credentials.api_access_token)
          return true
        end
      end

      render json: { error: 'unauthorized' }, status: :unauthorized
    end
  end
end 