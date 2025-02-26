module Api
  class AddressController < BaseController
    def convert_to_parts
      begin
        raw_address = params.require(:address)
        
        parts = AiService.parse_full_address(raw_address)
        render json: { 
          success: true, 
          parts: parts
        }
      rescue ActionController::ParameterMissing => e
        render json: { 
          success: false, 
          error: "missing required parameter: address"
        }, status: :bad_request
      rescue AiService::MissingAddressPartsError => e
        render json: { 
          success: false, 
          error: e.message 
        }, status: :unprocessable_entity
      rescue => e
        render json: { 
          success: false, 
          error: "error processing address: #{e.message}" 
        }, status: :internal_server_error
      end
    end
  end
end 