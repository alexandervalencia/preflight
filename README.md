<p align="center">
  <img src="docs/Preflight_splash.png" alt="Preflight" width="400">
</p>

<p align="center">
  Review your branches like GitHub pull requests — before pushing upstream.
</p>

---

Preflight is a local-first tool for self-reviewing your work. Run `preflight push` from any repo to open a local PR with diffs, commits, and a description editor. When you're ready, export it as a real GitHub PR with one click.

## Install

### Prerequisites

- [Devbox](https://www.jetify.com/devbox) 0.16+
- [Go](https://go.dev) 1.22+ (to build the CLI)
- [GitHub CLI](https://cli.github.com) (`gh`) for exporting PRs to GitHub

### Build

```bash
git clone <this-repo>
cd preflight
devbox run -- bundle install
devbox run -- bin/rails db:prepare

# Build the CLI
cd cli && go build -o ../tmp/preflight . && cd ..

# Add to your PATH
ln -sf "$(pwd)/tmp/preflight" /usr/local/bin/preflight
```

## Usage

From any git repository, on a feature branch:

```bash
preflight push
```

This will:
1. Start the preflight server (if not already running)
2. Create a local PR for your current branch
3. Open it in your browser

From there you can:
- Write a description with full GitHub Flavored Markdown
- Review diffs (split or unified) and commits
- Upload images (stored locally, converted to placeholders on export)
- Check off task list items
- Export to GitHub as a draft PR (pushes the branch for you)

### Other commands

```bash
preflight open          # Open the existing PR for the current branch
preflight list          # List all open preflight PRs (no server needed)
preflight server start  # Start the server manually
preflight server stop   # Stop the server
preflight server restart
preflight push --base develop  # Compare against a specific base branch
```

## How it works

Preflight is two things in one package:

- A **Go CLI** (`preflight`) that manages the server and talks to it via HTTP
- A **Rails app** that serves the browser UI and reads your git repos directly

Data lives in `~/.preflight/` (database, logs, uploaded images). The server auto-starts on `preflight push` and shuts down after 4 hours of inactivity.

## Development

```bash
devbox run -- bin/rails server    # Start the server (localhost:4500)
devbox run -- bin/rails test      # Run tests
```

## Stack

- Rails 8.1, Ruby 3.4, SQLite, Puma, Propshaft
- [Commonmarker](https://github.com/gjtorikian/commonmarker) for GFM markdown
- [Rouge](https://github.com/rouge-ruby/rouge) for syntax-highlighted diffs
- [Stimulus](https://stimulus.hotwired.dev) for interactive UI
- Go + [Cobra](https://github.com/spf13/cobra) for the CLI
- Icons from [Octicons](https://primer.style/octicons)
