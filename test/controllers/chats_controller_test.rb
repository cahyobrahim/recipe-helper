require "test_helper"
require "uri"

class ChatsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  # Job status and answers live in Rails.cache, which now persists between
  # tests, so start each case from a clean slate.
  setup { Rails.cache.clear }

  test "rejects an empty ingredient list" do
    post chats_path, params: { ingredients: [ "" ], staples: "1" }

    assert_response :success
    assert_select "[role=alert]", text: /Pick at least one ingredient/
  end

  test "serves structured recipe cards after the background job finishes" do
    with_fake_gemini(fake_client(recipes_json)) do
      perform_enqueued_jobs(only: RecipeGenerationJob) do
        post chats_path, params: { ingredients: [ "Chicken", "Rice" ], staples: "1" }
      end
    end

    assert_response :redirect
    token = token_from(response.location)

    get status_chat_path(token), as: :json
    assert_response :success

    payload = JSON.parse(response.body)
    assert_equal "done", payload["state"]
    assert_includes payload["html"], "Chicken Rice"
    assert_includes payload["html"], "data-controller=\"cook-mode clipboard servings\""
    assert_includes payload["html"], "400 g"
  end

  test "redirects to a pending page while the job runs" do
    post chats_path, params: { ingredients: [ "Chicken", "Rice" ], staples: "1" }

    assert_response :redirect
    token = token_from(response.location)

    follow_redirect!
    assert_response :success
    assert_select "[data-controller~=recipe-status]"
    assert_select "[data-recipe-status-url-value='#{status_chat_path(token)}']"
    assert_select "[data-recipe-status-target=results]"
    assert_select "[data-ingredient-picker-selected-value*='Chicken']"
  end

  test "renders the no-match state" do
    response_body = { message: "Try adding an onion.", recipes: [] }.to_json

    with_fake_gemini(fake_client(response_body)) do
      perform_enqueued_jobs(only: RecipeGenerationJob) do
        post chats_path, params: { ingredients: [ "Rice" ], staples: "0" }
      end
    end

    token = token_from(response.location)
    get status_chat_path(token), as: :json

    payload = JSON.parse(response.body)
    assert_equal "done", payload["state"]
    assert_includes payload["html"], "Nothing quite fits yet"
    assert_includes payload["html"], "Add more ingredients"
  end

  test "falls back to markdown when the response is not JSON" do
    with_fake_gemini(fake_client("## Chicken Rice\n\n- **Time:** 20 min")) do
      perform_enqueued_jobs(only: RecipeGenerationJob) do
        post chats_path, params: { ingredients: [ "Chicken" ], staples: "1" }
      end
    end

    token = token_from(response.location)
    get status_chat_path(token), as: :json

    payload = JSON.parse(response.body)
    assert_equal "done", payload["state"]
    assert_includes payload["html"], "markdown-body"
    assert_includes payload["html"], "Chicken Rice"
  end

  test "shows Gemini errors to the user" do
    client = fake_client(nil, error: "Gemini is slow or busy right now.")

    with_fake_gemini(client) do
      perform_enqueued_jobs(only: RecipeGenerationJob) do
        post chats_path, params: { ingredients: [ "Chicken" ], staples: "1" }
      end
    end

    token = token_from(response.location)
    get status_chat_path(token), as: :json

    payload = JSON.parse(response.body)
    assert_equal "error", payload["state"]
    assert_includes payload["html"], "Gemini is slow or busy"
  end

  test "throttles repeated recipe requests from one ip" do
    ip = "198.51.100.#{rand(1..254)}"
    limit = Integer(ENV.fetch("CHAT_IP_LIMIT", "10"))

    limit.times do
      post chats_path, params: { ingredients: [ "Chicken" ], staples: "1" },
                       headers: { "REMOTE_ADDR" => ip }
      assert_response :redirect
    end

    post chats_path, params: { ingredients: [ "Chicken" ], staples: "1" },
                     headers: { "REMOTE_ADDR" => ip }

    assert_response :too_many_requests
    assert response.headers["Retry-After"].to_i.positive?
    assert_select "h1", "Too many recipe requests"
  end

  test "redirects to the home page for an unknown request token" do
    get chat_path("does-not-exist")

    assert_redirected_to root_path
  end

  test "reports an expired request while polling" do
    get status_chat_path("does-not-exist"), as: :json

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal "error", payload["state"]
    assert_includes payload["html"], "This request has expired"
  end

  test "reuses a cached answer for the same ingredients" do
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    payload = recipes_json
    calls = 0
    client = Object.new
    client.define_singleton_method(:generate) do |*, **|
      calls += 1
      payload
    end

    with_fake_gemini(client) do
      perform_enqueued_jobs(only: RecipeGenerationJob) do
        post chats_path, params: { ingredients: [ "Lentils", "Spinach" ], staples: "1" },
                         headers: { "REMOTE_ADDR" => "203.0.113.10" }
      end
      assert_response :redirect

      post chats_path, params: { ingredients: [ "Spinach", "Lentils" ], staples: "1" },
                       headers: { "REMOTE_ADDR" => "203.0.113.11" }
      assert_response :success
      assert_select "h3", "Chicken Rice"
    end

    assert_equal 1, calls
  ensure
    Rails.cache = original_cache
  end

  private

  def token_from(location)
    URI.parse(location).path.split("/").reject(&:empty?).last
  end

  def fake_client(response = nil, error: nil)
    Object.new.tap do |client|
      client.define_singleton_method(:generate) do |*, **|
        raise GeminiClient::Error, error if error

        response
      end
    end
  end

  # Minitest 6 no longer ships minitest/mock, so swap the constructor directly.
  def with_fake_gemini(client)
    original_new = GeminiClient.method(:new)
    GeminiClient.define_singleton_method(:new) { |*| client }
    yield
  ensure
    GeminiClient.define_singleton_method(:new, original_new)
  end

  def recipes_json
    {
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
          missing: [],
          steps: [ "Cook the rice", "Fry the chicken" ]
        }
      ]
    }.to_json
  end
end
