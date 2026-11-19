# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-11-20

First tagged release.

### Added

- Ingredient picker backed by TheMealDB, with search, quick adds, and free-text entry.
- Recipe suggestions from Google Gemini, rendered as structured recipe cards with a
  sanitized Markdown fallback.
- Ingredient quantities and per-recipe serving counts, with client-side serving
  scaling that needs no extra API call.
- Background recipe generation: requests return immediately while the page polls a
  status endpoint until results arrive.
- Cook mode, copy, and print actions for each recipe.
- 24-hour caching of successful answers.
- Rate limiting (10 requests/hour/IP and 100/hour globally by default) plus Gemini
  cost caps.
- Warm, accessible kitchen-inspired UI.

### Changed

- Recipe requests now redirect to a pending page instead of blocking on the API.

[Unreleased]: https://github.com/cahyobrahim/recipe-helper/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/cahyobrahim/recipe-helper/releases/tag/v0.1.0
