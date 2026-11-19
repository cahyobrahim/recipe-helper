require "securerandom"

class ChatsController < ApplicationController
  def new
    @ingredients = []
    @staples = true
  end

  # Landing page after a recipe request has been queued. Renders the pending
  # state, or the finished result when the job already completed.
  def show
    token = params[:id].to_s
    entry = status_entry(token)

    if entry.blank?
      redirect_to(root_path) and return
    end

    @ingredients = Array(entry["ingredients"])
    @staples = entry["staples"] != false

    case entry["state"]
    when "done"
      @result = RecipeResult.from_json(entry["answer"])
      @answer = entry["answer"] unless @result
    when "error"
      @error = entry["message"]
    else
      @token = token
    end

    render :new
  end

  def create
    @ingredients = sanitize_ingredients
    @staples = params[:staples] == "1"

    if @ingredients.empty?
      @error = "Pick at least one ingredient."
      return render(:new)
    end

    generator = RecipeGenerator.new(ingredients: @ingredients, staples: @staples)

    # A duplicate request within the cache window can still render immediately.
    if (answer = generator.cached_answer)
      @result = RecipeResult.from_json(answer)
      @answer = answer unless @result
      render :new
    else
      enqueue_generation
    end
  end

  # Polled by the recipe-status Stimulus controller while a job is running.
  def status
    response.headers["Cache-Control"] = "no-store"
    entry = status_entry(params[:id].to_s)

    if entry.blank?
      render json: { state: "error", html: status_error_html("This request has expired. Please start again.") }
    elsif entry["state"] == "done"
      render json: { state: "done", html: results_html(entry["answer"]) }
    elsif entry["state"] == "error"
      render json: { state: "error", html: status_error_html(entry["message"]) }
    else
      render json: { state: "running" }
    end
  end

  private

  def sanitize_ingredients
    Array(params[:ingredients])
      .map { |item| item.to_s.strip.first(40) }
      .reject(&:blank?)
      .uniq
      .first(30)
  end

  def enqueue_generation
    token = SecureRandom.uuid

    RecipeGenerationJob.write_status(token, {
      "state" => "running",
      "ingredients" => @ingredients,
      "staples" => @staples
    })
    RecipeGenerationJob.perform_later(token, @ingredients, @staples)

    redirect_to chat_path(token)
  end

  def status_entry(token)
    Rails.cache.read(RecipeGenerationJob.status_key(token))
  end

  # The polling endpoint is requested as JSON, so force the HTML template format
  # when rendering the fragment the browser swaps into the page.
  def results_html(answer)
    result = RecipeResult.from_json(answer)

    if result&.recipes&.any?
      render_to_string(partial: "chats/results", formats: [ :html ],
                       locals: { result: result, answer: nil })
    elsif result
      render_to_string(partial: "chats/no_match", formats: [ :html ],
                       locals: { message: result.message })
    else
      render_to_string(partial: "chats/results", formats: [ :html ],
                       locals: { result: nil, answer: answer })
    end
  end

  def status_error_html(message)
    render_to_string(partial: "chats/status_error", formats: [ :html ],
                     locals: { message: message })
  end
end
