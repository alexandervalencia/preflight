<p align="center">
  <img src="docs/Preflight_splash.png" alt="Preflight" width="400">
</p>

<p align="center">
  Review your branches like GitHub pull requests — before pushing upstream.
</p>

---

Preflight gives you a local pull request experience so you can self-review your work before anyone else sees it. Write your description, review your diffs, and when everything looks right, export it as a real GitHub PR with one click.

No notifications. No draft PR clutter. Just you and your code.

## Install

```bash
brew tap alexandervalencia/tap
brew install preflight
```

Optionally, install the [GitHub CLI](https://cli.github.com) (`gh`) to export PRs directly to GitHub from Preflight.

## Quick start

Switch to a feature branch in any git repo, then:

```bash
preflight push
```

That's it. Preflight starts a local server, creates a PR for your branch, and opens it in your browser.

## What you can do

**Write your PR description** with full GitHub Flavored Markdown — headings, task lists, tables, code blocks, images, and more. Toggle between Write and Preview to see how it'll look.

**Review your changes** with syntax-highlighted diffs in split or unified view. Browse commit-by-commit or see all files changed at once.

**Check off task lists** right in the description — checkboxes are interactive and save automatically.

**Upload images** to illustrate your changes. Images are stored locally and converted to placeholders when you export, so you can re-upload them on GitHub.

**Export to GitHub** when you're ready. Preflight pushes your branch, creates a draft PR with your title and description, and shows you a link. If you have multiple remotes (e.g., a fork), you can choose where to push.

## Commands

```bash
preflight push                 # Create or open a PR for the current branch
preflight push --base develop  # Compare against a specific base branch
preflight open                 # Open the existing PR in your browser
preflight list                 # List all open preflight PRs
preflight server stop          # Stop the server
preflight server start         # Start the server manually
preflight server restart       # Restart the server
```

The server starts automatically on `preflight push` and shuts down after 4 hours of inactivity. You don't need to manage it.

## How it works

Preflight reads directly from your local git repos — no cloning, no syncing, no uploads. When you refresh the page, you see your latest commits. It's a Rails app that runs on `localhost:4500`, managed by a small Go CLI.

Data lives in `~/.preflight/` (database, logs, uploaded images).

---

## Contributing

### Prerequisites

- [Devbox](https://www.jetify.com/devbox) 0.16+
- [Go](https://go.dev) 1.22+

### Setup

```bash
git clone <this-repo>
cd preflight
devbox run -- bundle install
devbox run -- bin/rails db:prepare
```

### Development

```bash
devbox run -- bin/rails server    # Start the server (localhost:4500)
devbox run -- bin/rails test      # Run tests
```

To build the CLI locally:

```bash
cd cli && go build -o ../tmp/preflight . && cd ..
ln -sf "$(pwd)/tmp/preflight" /usr/local/bin/preflight
```

### Stack

- Rails 8.1, Ruby 3.4, SQLite, Puma, Propshaft
- [Commonmarker](https://github.com/gjtorikian/commonmarker) for GFM markdown
- [Rouge](https://github.com/rouge-ruby/rouge) for syntax-highlighted diffs
- [Stimulus](https://stimulus.hotwired.dev) for interactive UI
- Go + [Cobra](https://github.com/spf13/cobra) for the CLI
- Icons from [Octicons](https://primer.style/octicons)
