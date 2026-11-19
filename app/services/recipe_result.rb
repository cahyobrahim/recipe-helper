require "json"

# Shared amount formatting so server-rendered text and client-side scaling stay
# visually consistent.
module QuantityFormat
  FRACTIONS = [ [ 0.25, "¼" ], [ 0.33, "⅓" ], [ 0.5, "½" ], [ 0.67, "⅔" ], [ 0.75, "¾" ] ].freeze
  METRIC_UNITS = %w[g ml kg l oz lb].freeze

  def self.call(value, unit = "")
    unit_name = unit.to_s.strip
    return unit_name if unit_name.downcase.include?("taste")

    amount = value.to_f
    return "" unless amount.positive?

    if METRIC_UNITS.include?(unit_name.downcase)
      return "#{ [ amount.round, 1 ].max } #{unit_name}".strip
    end

    whole = amount.floor
    fraction = amount - whole
    candidate, glyph = FRACTIONS.min_by { |value, _| (fraction - value).abs }
    difference = (fraction - candidate).abs

    fraction_text = if difference <= 0.06
      glyph
    elsif fraction >= 0.1
      fraction.round(2).to_s
    else
      ""
    end

    number = if whole.positive?
      "#{whole}#{fraction_text}"
    else
      fraction_text.presence || amount.round(2).to_s
    end

    "#{number} #{unit_name}".strip
  end
end

# Plain value objects for the structured JSON returned by Gemini.
# No database involved — this just turns a JSON string into view-ready recipes.
class RecipeResult
  Ingredient = Struct.new(:name, :quantity, :unit, keyword_init: true) do
    def display_amount
      QuantityFormat.call(quantity, unit)
    end
  end

  Recipe = Struct.new(:name, :time, :servings, :ingredients, :uses, :missing, :steps, keyword_init: true) do
    def to_plain_text
      lines = [ name.to_s ]
      lines << "Servings: #{servings}" if servings
      lines << "Time: #{time}" if time.present?

      if ingredients.any?
        lines << ""
        lines << "Ingredients:"
        ingredients.each { |ingredient| lines << "- #{ingredient.display_amount} #{ingredient.name}".strip }
      elsif uses.any?
        lines << "Uses: #{uses.join(", ")}"
      end

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

    servings = value_for(item, "servings").to_i

    Recipe.new(
      name: value_for(item, "name").to_s.strip.presence || "Untitled dish",
      time: value_for(item, "time").to_s.strip.presence,
      servings: servings.positive? ? servings : nil,
      ingredients: Array(value_for(item, "ingredients")).filter_map { |part| build_ingredient(part) }.first(12),
      uses: string_list(value_for(item, "uses")),
      missing: string_list(value_for(item, "missing")),
      steps: string_list(value_for(item, "steps")).first(8)
    )
  end

  def self.build_ingredient(item)
    return nil unless item.is_a?(Hash)

    name = value_for(item, "name").to_s.strip.presence
    return nil unless name

    raw_quantity = value_for(item, "quantity")
    quantity = if raw_quantity.is_a?(Numeric)
      raw_quantity.to_f
    elsif raw_quantity.to_s.match?(/\A-?\d+(?:\.\d+)?\z/)
      raw_quantity.to_f
    end

    Ingredient.new(name: name, quantity: quantity, unit: value_for(item, "unit").to_s.strip)
  end

  def self.value_for(hash, key)
    hash.key?(key) ? hash[key] : hash[key.to_sym]
  end

  def self.string_list(value)
    Array(value).map { |item| item.to_s.strip }.reject(&:empty?).first(8)
  end
end
