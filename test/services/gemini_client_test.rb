require "test_helper"

class GeminiClientTest < ActiveSupport::TestCase
  test "caps generation cost in the request payload" do
    original_start = Net::HTTP.method(:start)
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response.define_singleton_method(:body) do
      { candidates: [ { content: { parts: [ { text: "{}" } ] } } ] }.to_json
    end
    request_body = nil

    Net::HTTP.define_singleton_method(:start) do |*, **, &block|
      http = Object.new
      http.define_singleton_method(:request) do |request|
        request_body = request.body
        response
      end
      block.call(http)
    end

    GeminiClient.new(api_key: "test-key").generate("hello", json_schema: { type: "OBJECT" })

    config = JSON.parse(request_body).fetch("generationConfig")
    assert_equal GeminiClient::MAX_OUTPUT_TOKENS, config.fetch("maxOutputTokens")
    assert_equal 1, config.fetch("candidateCount")
    assert_in_delta GeminiClient::TEMPERATURE, config.fetch("temperature"), 0.001
    assert_equal "application/json", config.fetch("responseMimeType")
  ensure
    Net::HTTP.define_singleton_method(:start, original_start)
  end
end
