require "json"

# Plain value objects for the structured JSON returned by Gemini.
# No database involved — this just turns a JSON string into view-ready recipes.
class RecipeResult
  Recipe = Struct.new(:name, :time, :uses, :missing, :steps, keyword_init: true) do
    def to_plain_text
      lines = [ name.to_s ]
      lines << "Time: #{time}" if time.present?
      lines << "Uses: #{uses.join(", ")}" if uses.any?
      lines << "Optional extras: #{missing.join(", ")}" if missing.any?
      lines << ""
      steps.each_with_index { |step, index| lines << "#{index + 1}. #{step}" }
      lines.join("\n")
    end
  end

  attr_reader :message, :recipes

  def initialize(message:, recipes:)
    @message = message.to_s.presence
    @recipes = recipes
  end

  def self.from_json(raw)
    data = JSON.parse(raw.to_s)
    return nil unless data.is_a?(Hash)

    recipes = Array(value_for(data, "recipes")).filter_map { |item| build_recipe(item) }
    new(message: value_for(data, "message"), recipes: recipes)
  rescue JSON::ParserError, TypeError
    nil
  end

  def self.build_recipe(item)
    return nil unless item.is_a?(Hash)

    Recipe.new(
      name: value_for(item, "name").to_s.strip.presence || "Untitled dish",
      time: value_for(item, "time").to_s.strip.presence,
      uses: string_list(value_for(item, "uses")),
      missing: string_list(value_for(item, "missing")),
      steps: string_list(value_for(item, "steps")).first(8)
    )
  end

  def self.value_for(hash, key)
    hash.key?(key) ? hash[key] : hash[key.to_sym]
  end

  def self.string_list(value)
    Array(value).map { |item| item.to_s.strip }.reject(&:empty?).first(8)
  end
end
