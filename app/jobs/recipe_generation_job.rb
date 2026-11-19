class RecipeGenerationJob < ApplicationJob
  queue_as :default

  STATUS_TTL = 10.minutes
  EMPTY_RESPONSE = "No response returned."

  # token is a random UUID created by the controller. The status hash lives in
  # Rails.cache so the polling endpoint can read it from any worker.
  def perform(token, ingredients, staples)
    generator = RecipeGenerator.new(ingredients: ingredients, staples: staples)
    answer = generator.cached_answer || generator.generate

    if answer.blank? || answer == EMPTY_RESPONSE
      self.class.write_status(token, {
        "state" => "error",
        "message" => "Gemini returned an empty response. Please try again."
      })
    else
      self.class.write_status(token, { "state" => "done", "answer" => answer })
    end
  rescue GeminiClient::Error => e
    self.class.write_status(token, { "state" => "error", "message" => e.message })
  rescue => e
    Rails.logger.error("[recipe-generation] #{e.class}: #{e.message}")
    self.class.write_status(token, {
      "state" => "error",
      "message" => "Something went wrong while generating recipes. Please try again."
    })
    raise
  end

  def self.status_key(token)
    "recipe-helper:job:#{token}"
  end

  def self.write_status(token, payload)
    Rails.cache.write(status_key(token), payload, expires_in: STATUS_TTL)
  end
end
