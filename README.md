# Recipe Helper

A small Rails 8.1 app that suggests recipes from the ingredients you have at
home using the Google Gemini API. There is no database — the app is stateless.

## Requirements

- Ruby 4.0.9 (see `.ruby-version`)
- Bundler
- A Google Gemini API key

## Setup

1. Install gems:

   ```sh
   bundle install
   ```

2. Create your local environment file and add your API key:

   ```sh
   cp .env.example .env
   ```

   | Variable | Required | Description |
   | --- | --- | --- |
   | `GEMINI_API_KEY` | yes | Google Gemini API key |
   | `GEMINI_MODELS` | no | Comma-separated model fallback list (default: `gemini-3.8-flash,gemini-3.6-flash`) |

   `.env` is loaded only in development and test. In production, inject
   `GEMINI_API_KEY` as a container secret (see `config/deploy.yml`).

3. Start the web server and the Tailwind watcher:

   ```sh
   bin/dev
   ```

   Then visit <http://localhost:3000>. To run only the Rails server, use
   `bin/rails server`.

   > **Windows PowerShell:** the `bin/*` scripts are shell scripts. Run
   > `ruby bin/rails server` and, in a second terminal,
   > `ruby bin/rails tailwindcss:watch` instead of `bin/dev`.

## How it works

- `GET /` renders an ingredient picker. The ingredient list comes from TheMealDB
  via `IngredientCatalog`, cached in `tmp/ingredients.json` for 24 hours.
- `POST /chats` builds a prompt from your selections and calls `GeminiClient`.
  The response is rendered as sanitized Markdown.

## Tests and checks

```sh
bin/rails test           # test suite
bin/rubocop              # lint
bin/brakeman --no-pager  # security scan
bin/bundler-audit        # gem vulnerability scan
```

On Windows, prefix these with `ruby` (for example, `ruby bin/rails test`).

## Deployment

Docker and Kamal scaffolding is included. Export `GEMINI_API_KEY` (or fetch it
from your password manager) before running `bin/kamal deploy`; `.kamal/secrets`
reads it from the environment, so no raw key is ever committed.
