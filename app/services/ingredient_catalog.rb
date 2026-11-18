require "net/http"
require "json"

# Loads the ingredient list from TheMealDB instead of hard-coding it.
# Layers: memory (1 day) -> tmp/ingredients.json (1 day) -> live API.
# If the API is down, it falls back to the last saved file, or an empty list.
class IngredientCatalog
  URL = "https://www.themealdb.com/api/json/v1/1/list.php?i=list".freeze
  CACHE_FILE = Rails.root.join("tmp", "ingredients.json")
  TTL = 24.hours
  RETRY_AFTER = 5.minutes

  @mutex = Mutex.new
  @names = nil
  @expires_at = nil

  class << self
    def all
      @mutex.synchronize do
        if @names.nil? || Time.current > @expires_at
          names = fresh_file_names || fetch_and_store

          if names.present?
            @names = names
            @expires_at = Time.current + TTL
          else
            @names = read_file || []
            @expires_at = Time.current + RETRY_AFTER
          end
        end

        @names
      end
    end

    private

    def fetch_and_store
      names = fetch_remote
      write_file(names) if names.present?
      names
    end

    def fetch_remote
      uri = URI(URL)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                                 open_timeout: 5, read_timeout: 8) do |http|
        http.get(uri.request_uri)
      end
      return nil unless response.is_a?(Net::HTTPSuccess)

      meals = JSON.parse(response.body)["meals"]
      Array(meals)
        .filter_map { |meal| (meal["strIngredient"] || meal["strIngredient1"]).to_s.strip.presence }
        .uniq
        .sort_by(&:downcase)
    rescue StandardError => e
      Rails.logger.warn("IngredientCatalog fetch failed: #{e.class}")
      nil
    end

    def fresh_file_names
      return nil unless File.exist?(CACHE_FILE)
      return nil if Time.current - File.mtime(CACHE_FILE) > TTL

      read_file
    end

    def read_file
      return nil unless File.exist?(CACHE_FILE)

      names = JSON.parse(File.read(CACHE_FILE))
      names.is_a?(Array) && names.any? ? names : nil
    rescue JSON::ParserError
      nil
    end

    def write_file(names)
      File.write(CACHE_FILE, names.to_json)
    rescue StandardError => e
      Rails.logger.warn("IngredientCatalog cache write failed: #{e.class}")
    end
  end
end
