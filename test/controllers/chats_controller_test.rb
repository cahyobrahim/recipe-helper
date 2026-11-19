require "test_helper"

class ChatsControllerTest < ActionDispatch::IntegrationTest
  test "rejects an empty ingredient list" do
    post chats_path, params: { ingredients: [ "" ], staples: "1" }

    assert_response :success
    assert_select "[role=alert]", text: /Pick at least one ingredient/
  end

  test "renders structured recipe cards" do
    with_fake_gemini(fake_client(recipes_json)) do
      post chats_path, params: { ingredients: [ "Chicken", "Rice" ], staples: "1" }
    end

    assert_response :success
    assert_select "h3", "Chicken Rice"
    assert_select "[data-controller~=cook-mode]"
    assert_select "[data-controller~=clipboard]"
  end

  test "renders the no-match state" do
    response = { message: "Try adding an onion.", recipes: [] }.to_json

    with_fake_gemini(fake_client(response)) do
      post chats_path, params: { ingredients: [ "Rice" ], staples: "0" }
    end

    assert_response :success
    assert_select "h2", "Nothing quite fits yet"
    assert_select "a", text: "Add more ingredients"
  end

  test "falls back to markdown when the response is not JSON" do
    with_fake_gemini(fake_client("## Chicken Rice\n\n- **Time:** 20 min")) do
      post chats_path, params: { ingredients: [ "Chicken" ], staples: "1" }
    end

    assert_response :success
    assert_select ".markdown-body"
  end

  test "shows Gemini errors to the user" do
    client = fake_client(nil, error: "Gemini is slow or busy right now.")

    with_fake_gemini(client) do
      post chats_path, params: { ingredients: [ "Chicken" ], staples: "1" }
    end

    assert_response :success
    assert_select "[role=alert]", text: /Gemini is slow or busy/
  end

  test "throttles repeated recipe requests from one ip" do
    ip = "198.51.100.#{rand(1..254)}"
    limit = Integer(ENV.fetch("CHAT_IP_LIMIT", "10"))

    limit.times do
      with_fake_gemini(fake_client(recipes_json)) do
        post chats_path, params: { ingredients: [ "Chicken" ], staples: "1" },
                         headers: { "REMOTE_ADDR" => ip }
      end
      assert_response :success
    end

    with_fake_gemini(fake_client(recipes_json)) do
      post chats_path, params: { ingredients: [ "Chicken" ], staples: "1" },
                       headers: { "REMOTE_ADDR" => ip }
    end

    assert_response :too_many_requests
    assert response.headers["Retry-After"].to_i.positive?
    assert_select "h1", "Too many recipe requests"
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
      post chats_path, params: { ingredients: [ "Lentils", "Spinach" ], staples: "1" },
                       headers: { "REMOTE_ADDR" => "203.0.113.10" }
      assert_response :success

      post chats_path, params: { ingredients: [ "Spinach", "Lentils" ], staples: "1" },
                       headers: { "REMOTE_ADDR" => "203.0.113.11" }
      assert_response :success
    end

    assert_equal 1, calls
  ensure
    Rails.cache = original_cache
  end

  private

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
          uses: [ "Chicken", "Rice" ],
          missing: [],
          steps: [ "Cook the rice", "Fry the chicken" ]
        }
      ]
    }.to_json
  end
end
