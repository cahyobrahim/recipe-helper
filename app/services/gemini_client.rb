require "net/http"
require "json"

class GeminiClient
  class Error < StandardError; end
  class Busy < Error; end

  MODELS = ENV.fetch("GEMINI_MODELS", "gemini-3.8-flash,gemini-3.6-flash").split(",").map(&:strip)
  READ_TIMEOUT = 45

  def initialize(api_key: ENV["GEMINI_API_KEY"])
    @api_key = api_key
    raise Error, "GEMINI_API_KEY is not set" if @api_key.blank?
  end

  def generate(prompt, system: nil, json_schema: nil)
    last_error = nil

    MODELS.each do |model|
      2.times do |attempt|
        begin
          return request(model, prompt, system, json_schema)
        rescue Net::ReadTimeout, Net::OpenTimeout
          last_error = "#{model} timed out"
          break
        rescue Busy => e
          last_error = e.message
          sleep(1 + attempt)
        end
      end
    end

    raise Error, "Gemini is slow or busy right now. Please try again in a minute. (#{last_error})"
  end

  private

  def request(model, prompt, system, json_schema)
    uri = URI("https://generativelanguage.googleapis.com/v1beta/models/#{model}:generateContent")
    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/json"
    req["x-goog-api-key"] = @api_key

    payload = { contents: [ { parts: [ { text: prompt } ] } ] }
    payload[:system_instruction] = { parts: [ { text: system } ] } if system
    if json_schema
      payload[:generationConfig] = {
        responseMimeType: "application/json",
        responseSchema: json_schema
      }
    end
    req.body = payload.to_json

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                               open_timeout: 10, read_timeout: READ_TIMEOUT) do |http|
      http.request(req)
    end

    body = JSON.parse(response.body)

    unless response.is_a?(Net::HTTPSuccess)
      message = body.dig("error", "message") || "Request failed (#{response.code})"
      raise Busy, message if [ 429, 503 ].include?(response.code.to_i)
      raise Error, message
    end

    body.dig("candidates", 0, "content", "parts", 0, "text") || "No response returned."
  end
end
