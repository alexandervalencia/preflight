# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Preflight is a local-first Rails app for reviewing git branches like GitHub pull requests — before pushing upstream. Users register local repositories by filesystem path, then compare branches to create PRs with commit-by-commit review, per-file diffs, inline comments, and viewed-file tracking.

## Essential Commands

All commands must be prefixed with `devbox run --`:

- `devbox run -- bin/rails server` - Start dev server (localhost:3000)
- `devbox run -- bin/rails test` - Run all tests
- `devbox run -- bin/rails test test/path/to/file_test.rb` - Single test file
- `devbox run -- bin/rails test test/path/to/file_test.rb:42` - Single test
- `devbox run -- bundle install` - Install gems
- `devbox run -- bin/rails db:prepare` - Setup database

## Architecture

```
app/
  controllers/     # Thin controllers, one per resource
  helpers/         # View helpers (diff rendering, octicons, markdown)
  models/          # ActiveRecord models (LocalRepository, PullRequest)
  services/        # GitRepository — wraps git operations
  views/           # ERB templates, server-rendered
config/routes.rb   # GitHub-style nested routes (/:repository_name/pull/:id)
db/schema.rb       # SQLite, two tables
test/              # Minitest, mirrors app/ structure
```

## Stack

- Rails 8.1, Ruby 3.4, SQLite, Puma, Propshaft
- Rouge for syntax-highlighted diffs
- Devbox for reproducible environment (no system Ruby)
- No JavaScript framework — server-rendered HTML, Turbo for navigation
- Icons from primer.style/octicons via `octicon` helper

## Philosophy

**Server-rendered by default.** HTML is the primary interface. Reach for Turbo and Stimulus only when server rendering can't deliver the interaction. No SPAs, no client-side routing, no JSON APIs for what HTML can do.

**Lean into Rails.** Use the framework's conventions — RESTful resources, concerns, helpers, ERB partials. When Rails has an answer, use it. Don't introduce gems or abstractions for problems Rails already solves.

**Few abstractions, little indirection.** A new developer should read a controller action and understand the full request cycle. Avoid service objects unless the logic genuinely doesn't belong in a model or controller. Prefer explicit code over clever metaprogramming.

**Small dependency footprint.** Every gem is a liability. The Gemfile should stay short. If you can write it in 50 lines, don't add a gem.

**SQLite is the database.** This is a single-user local tool. SQLite is the right choice — no Postgres, no Redis, no background job infrastructure unless the need is proven.

**Test behavior, not implementation.** Integration and system tests over isolated unit tests. Test what the user sees and does, not internal method signatures.

**Code reads like prose.** Descriptive names, short methods, minimal comments. If code needs a comment to explain *what* it does, rewrite the code. Comments explain *why*, never *what*.

## Routing Convention

Routes follow GitHub's URL structure: `/:repository_name/pull/:id/files`, `/:repository_name/pull/:id/commits`. Repository names are slug-based, not ID-based. Maintain this pattern for new routes.

## Development Notes

- `GitRepository` service wraps all git CLI interactions — don't shell out to git elsewhere
- Diffs are rendered server-side with Rouge highlighting in `DiffHelper`
- The `octicon` helper in `OcticonHelper` renders SVG icons — see primer.style/octicons for available icons
- Viewed-file tracking flags "New changes" when later commits touch previously-viewed files
