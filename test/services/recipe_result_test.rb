require "test_helper"

class RecipeResultTest < ActiveSupport::TestCase
  test "parses structured JSON into recipes" do
    payload = {
      message: "",
      recipes: [
        {
          name: "Chicken Rice",
          time: "20 min",
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
    assert_equal [ "Chicken", "Rice" ], recipe.uses
    assert_equal [ "Soy sauce" ], recipe.missing
    assert_equal 3, recipe.steps.size
  end

  test "reads symbol keys and tolerates missing fields" do
    result = RecipeResult.from_json({ recipes: [ { name: "Toast" } ] }.to_json)

    assert_equal "Toast", result.recipes.first.name
    assert_equal [], result.recipes.first.uses
    assert_equal [], result.recipes.first.steps
  end

  test "returns nil for invalid JSON" do
    assert_nil RecipeResult.from_json("not json")
    assert_nil RecipeResult.from_json("[]")
  end

  test "plain text includes numbered steps" do
    recipe = RecipeResult::Recipe.new(name: "Toast", time: "5 min", uses: [ "Bread" ], missing: [], steps: [ "Toast bread", "Add butter" ])

    assert_includes recipe.to_plain_text, "1. Toast bread"
    assert_includes recipe.to_plain_text, "Time: 5 min"
  end
end
