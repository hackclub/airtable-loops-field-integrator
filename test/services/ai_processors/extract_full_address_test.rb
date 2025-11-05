require "test_helper"
require "minitest/mock"

class AiProcessors::ExtractFullAddressTest < ActiveSupport::TestCase
  test "extracts address components from input" do
    # Stub the AI client to return mock data (must match schema field names: camelCase)
    mock_response = {
      "addressLine1" => "123 Main St",
      "addressLine2" => "Apt 4B",
      "addressCity" => "Springfield",
      "addressState" => "IL",
      "addressZipCode" => "62704",
      "addressCountry" => "US"
    }

    Ai::Client.stub(:get_or_generate, mock_response) do
      result = AiProcessors::ExtractFullAddress.call(raw_input: "123 Main St, Apt 4B, Springfield, IL 62704")

      assert_equal "123 Main St", result["addressLine1"]
      assert_equal "Apt 4B", result["addressLine2"]
      assert_equal "Springfield", result["addressCity"]
      assert_equal "IL", result["addressState"]
      assert_equal "62704", result["addressZipCode"]
      assert_equal "US", result["addressCountry"]
    end
  end

  test "returns empty hash for blank input" do
    result = AiProcessors::ExtractFullAddress.call(raw_input: "")
    assert_equal({}, result)
  end

  test "handles optional addressLine2" do
    mock_response = {
      "addressLine1" => "123 Main St",
      "addressLine2" => nil,
      "addressCity" => "Springfield",
      "addressState" => "IL",
      "addressZipCode" => "62704",
      "addressCountry" => "US"
    }

    Ai::Client.stub(:get_or_generate, mock_response) do
      result = AiProcessors::ExtractFullAddress.call(raw_input: "123 Main St, Springfield, IL 62704")

      assert_equal "123 Main St", result["addressLine1"]
      assert_nil result["addressLine2"]
      assert_equal "Springfield", result["addressCity"]
    end
  end

  test "normalizes input before processing" do
    mock_response = {
      "addressLine1" => "123 Main St",
      "addressCity" => "Springfield",
      "addressState" => "IL",
      "addressZipCode" => "62704",
      "addressCountry" => "US"
    }

    Ai::Client.stub(:get_or_generate, mock_response) do
      result = AiProcessors::ExtractFullAddress.call(raw_input: "  123 Main St, Springfield, IL 62704  ")

      assert_equal "123 Main St", result["addressLine1"]
      assert_equal "Springfield", result["addressCity"]
    end
  end
end
