require "test_helper"

class RecipeResultTest < ActiveSupport::TestCase
  test "parses structured JSON into recipes" do
    payload = {
      message: "",
      recipes: [
        {
          name: "Chicken Rice",
          time: "20 min",
          servings: 2,
          ingredients: [
            { name: "Chicken", quantity: 400, unit: "g" },
            { name: "Rice", quantity: 1, unit: "cup" }
          ],
          uses: [ "Chicken", "Rice" ],
          missing: [ "Soy sauce" ],
          steps: [ "Cook the rice", "Fry the chicken", "Serve together" ]
        }
      ]
    }.to_json

    result = RecipeResult.from_json(payload)

    assert_equal 1, result.recipes.size
    recipe = result.recipes.first
    assert_equal "Chicken Rice", recipe.name
    assert_equal "20 min", recipe.time
    assert_equal 2, recipe.servings
    assert_equal 2, recipe.ingredients.size
    assert_equal "Chicken", recipe.ingredients.first.name
    assert_equal 400.0, recipe.ingredients.first.quantity
    assert_equal "400 g", recipe.ingredients.first.display_amount
    assert_equal [ "Chicken", "Rice" ], recipe.uses
    assert_equal [ "Soy sauce" ], recipe.missing
    assert_equal 3, recipe.steps.size
  end

  test "reads symbol keys and tolerates missing fields" do
    result = RecipeResult.from_json({ recipes: [ { name: "Toast" } ] }.to_json)

    assert_equal "Toast", result.recipes.first.name
    assert_nil result.recipes.first.servings
    assert_equal [], result.recipes.first.ingredients
    assert_equal [], result.recipes.first.uses
    assert_equal [], result.recipes.first.steps
  end

  test "returns nil for invalid JSON" do
    assert_nil RecipeResult.from_json("not json")
    assert_nil RecipeResult.from_json("[]")
  end

  test "plain text includes servings, amounts and numbered steps" do
    recipe = RecipeResult::Recipe.new(
      name: "Toast",
      time: "5 min",
      servings: 2,
      ingredients: [ RecipeResult::Ingredient.new(name: "Bread", quantity: 2, unit: "slice") ],
      uses: [ "Bread" ],
      missing: [],
      steps: [ "Toast bread", "Add butter" ]
    )

    assert_includes recipe.to_plain_text, "Servings: 2"
    assert_includes recipe.to_plain_text, "- 2 slice Bread"
    assert_includes recipe.to_plain_text, "1. Toast bread"
    assert_includes recipe.to_plain_text, "Time: 5 min"
  end

  test "formats fractional and metric amounts" do
    assert_equal "1½ cups", QuantityFormat.call(1.5, "cups")
    assert_equal "½", QuantityFormat.call(0.5, "")
    assert_equal "400 g", QuantityFormat.call(400, "g")
    assert_equal "to taste", QuantityFormat.call(0, "to taste")
  end
end
