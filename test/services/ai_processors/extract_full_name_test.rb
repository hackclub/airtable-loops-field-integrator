require "test_helper"
require "minitest/mock"

class AiProcessors::ExtractFullNameTest < ActiveSupport::TestCase
  test "extracts first and last name from input" do
    # Stub the AI client to return mock data (must match schema field names: camelCase)
    mock_response = {
      "firstName" => "John",
      "lastName" => "Doe"
    }

    Ai::Client.stub(:get_or_generate, mock_response) do
      result = AiProcessors::ExtractFullName.call(raw_input: "John Doe")

      assert_equal "John", result["firstName"]
      assert_equal "Doe", result["lastName"]
    end
  end

  test "returns empty hash for blank input" do
    result = AiProcessors::ExtractFullName.call(raw_input: "")
    assert_equal({}, result)
  end

  test "returns empty hash for nil input" do
    result = AiProcessors::ExtractFullName.call(raw_input: nil)
    assert_equal({}, result)
  end

  test "normalizes input before processing" do
    mock_response = {
      "firstName" => "Jane",
      "lastName" => "Smith"
    }

    Ai::Client.stub(:get_or_generate, mock_response) do
      result = AiProcessors::ExtractFullName.call(raw_input: "  Jane Smith  ")

      assert_equal "Jane", result["firstName"]
      assert_equal "Smith", result["lastName"]
    end
  end
end
