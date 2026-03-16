# Preflight CLI & GitHub Export — Design Spec

## Overview

Transform preflight from a local Rails web app into an installable CLI tool with a `preflight push` workflow. Users install via Homebrew, run `preflight push` from any repo to create a local PR for self-review, then export to GitHub as a real PR when ready.

## Target User

Individual developers on small teams who want to self-review their work before pushing upstream. Single-user, local-first — no auth, no multi-tenant.

## Architecture: B-lite

Two components in one Homebrew package:

1. **Go CLI binary** (`preflight`) — handles all terminal commands. Reads SQLite directly for simple queries (`list`). Talks to the Rails server via localhost HTTP for operations that need the full app (`push`, `open`). Manages the server process via PID file.

2. **Rails server with bundled Ruby** — the existing app, mostly unchanged. Adds JSON API endpoints for CLI communication. Ships with its own Ruby runtime (via Traveling Ruby or static build) so it never conflicts with the user's Ruby version manager (asdf, rbenv, rvm, devbox, etc.).

### System Diagram

```
┌─────────────────────────┐         ┌──────────────────────────────┐
│  User's Terminal         │         │  Rails Server (bundled Ruby)  │
│                          │  HTTP   │                               │
│  $ preflight push       ─┼────────>│  HTML Views (browser UI)      │
│  $ preflight list       ─┼─ SQLite │  API Endpoints (CLI ↔ server) │
│  $ preflight open       ─┼────────>│  GitRepository service        │
│  $ preflight server ... ─┼─ PID   │  SQLite (~/.preflight/db)     │
│                          │         │  Image uploads                │
└─────────────────────────┘         └──────────────────────────────┘
         │                                     │           │
         ▼                                     ▼           ▼
    ┌─────────┐                          ┌──────────┐ ┌────────┐
    │ Browser  │                          │ Git Repos │ │ gh CLI │
    └─────────┘                          └──────────┘ └────────┘
```

## Data Storage

All data lives in `~/.preflight/`:

```
~/.preflight/
  db.sqlite3           # All repos and PRs
  preflight.pid        # Server process tracking
  preflight.log        # Server output
  uploads/             # PR images
    <pr_id>/           # Scoped per-PR, deleted on close
      screenshot.png
```

The database location is configurable via environment variable for development.

## CLI Commands

### `preflight push [--base <branch>]`

The primary entry point. From any git repository:

1. Detects current branch and repo path
2. Errors if on the base branch ("nothing to review, you're on the default branch")
3. Auto-registers the repo in preflight's DB if not already registered
4. Auto-starts the server if not running (writes PID to `~/.preflight/preflight.pid`)
5. Creates a PR via `POST /api/pull_requests` (or finds existing one for this branch)
6. Opens browser to the PR show page, focused on the description field

**Base branch resolution:**
- If `--base` flag provided, use that
- Otherwise, default to the repo's default branch (main/master)

### `preflight open`

Opens browser to the existing preflight PR for the current branch. Errors if none exists. Auto-starts the server if not running.

### `preflight list`

Shows all active preflight PRs across all repos. Reads SQLite directly — no server needed.

```
REPO          BRANCH              CREATED
my-app        feature/auth        2 hours ago
other-repo    fix/login-bug       yesterday
```

### `preflight server start|stop|restart`

Manual server management:
- `start` — boots Rails, writes PID file, logs to `~/.preflight/preflight.log`
- `stop` — sends SIGTERM to PID
- `restart` — stop + start

## Server Lifecycle

- **Auto-start**: `preflight push` and `preflight open` start the server if not running
- **Auto-shutdown**: server tracks last request time; exits after ~30 minutes of inactivity
- **PID tracking**: `~/.preflight/preflight.pid` tracks the server process
- **Health check**: CLI pings `GET /api/status` to verify server is alive before making requests

## PR Lifecycle

```
1. CREATE     preflight push
              → PR created (status: open), browser opens to description editor

2. REVIEW     User reviews in browser
              → Diffs, commits, write description, add images
              → New commits/rebases show up on page refresh (fresh git reads)

3. EXPORT     "Create PR on GitHub" button in preflight UI
              → Shells out to gh pr create with title, description, base, head
              → Base branch: uses preflight PR's base_branch if it exists on remote,
                otherwise falls back to repo's default branch
              → Creates as draft by default
              → On success: shows link to GitHub PR

4. CLOSE      Automatic on successful GitHub export
              → PR status set to "closed", github_pr_url saved
              → Images in ~/.preflight/uploads/<pr_id>/ deleted
              → PR stays visible in preflight (read-only) for reference
```

### Edge Cases

- **User is on the base branch**: `preflight push` errors with clear message
- **PR already exists for branch**: `push` opens the existing PR instead of creating a duplicate
- **Branch deleted while PR is open**: PR show page displays "branch not found" state, allows closing
- **Force-push/rebase**: works naturally — fresh git reads on page load show new history
- **Base branch doesn't exist on GitHub remote**: fall back to repo's default branch for `gh pr create`, inform the user
- **PR already exists on GitHub for this branch**: detect via `gh pr list`, show link instead of create button
- **Repo has no remote**: hide GitHub export button entirely
- **`gh` not installed**: hide GitHub export button, show "install gh to enable GitHub export"

## Image Support in Descriptions

### Upload Flow

1. File input / drag-and-drop zone on the description editor
2. `POST /:repository_name/pull/:id/uploads` saves file to `~/.preflight/uploads/<pr_id>/`
3. Returns markdown image reference: `![filename](/_preflight/uploads/<pr_id>/filename.png)`
4. Inserted into description textarea at cursor position

### Serving

Rails serves images from `~/.preflight/uploads/` via a controller route at `/_preflight/uploads/:pr_id/:filename`.

### Constraints

- Scoped per-PR: `~/.preflight/uploads/<pr_id>/`
- Entire directory deleted when PR is closed
- 10MB max file size per image
- Supported formats: PNG, JPG, GIF, WebP
- No image editing, resizing, or thumbnails

### GitHub Export

Images are local-only in v1. On export, a warning informs the user that images won't appear in the GitHub PR. Image portability is a future enhancement.

## Changes to Existing Rails App

### Database

- Move SQLite DB location to `~/.preflight/db.sqlite3` (env var override for dev)
- Add `status` column to `pull_requests` (`open`/`closed`, default `open`)
- Add `github_pr_url` column to `pull_requests` (nullable, set on export)

### New Controllers

**`Api::PullRequestsController`**
- `POST /api/pull_requests` — accepts `repo_path`, `source_branch`, `base_branch`; auto-registers repo; returns PR URL as JSON
- `GET /api/status` — health check for CLI

**`UploadsController`**
- `POST /:repository_name/pull/:id/uploads` — saves image, returns markdown reference
- `GET /_preflight/uploads/:pr_id/:filename` — serves image files

**`GithubExportsController`**
- `POST /:repository_name/pull/:id/github_export` — runs `gh pr create`, marks PR closed, deletes images, returns GitHub URL

### View Changes

- PR show page: image upload zone in description editor
- PR show page: "Create PR on GitHub" button (conditionally shown)
- PR show page: closed state with link to GitHub PR
- PR index: filter by open/closed status

### Idle Shutdown

Middleware or background thread that tracks last request time. Exits the Puma process after ~30 minutes of no requests.

## Distribution (Homebrew)

### Package Structure

```
/usr/local/Cellar/preflight/
  bin/
    preflight              # Go binary (CLI)
  libexec/
    server/                # Rails app source
    ruby/                  # Bundled Ruby runtime
    vendor/                # Vendored gems
    bin/
      start-server         # Boots Rails with bundled Ruby
```

### Install Experience

```bash
brew tap <username>/preflight
brew install preflight
```

No `depends_on "ruby"` — Ruby is self-contained. Go binary compiled during install.

### Release Pipeline (GitHub Actions)

1. Build Go binary for darwin-arm64, darwin-amd64, linux-arm64, linux-amd64
2. Bundle Rails app + Ruby runtime per platform
3. Publish to GitHub Releases
4. Homebrew tap auto-updates formula

## Future Enhancements (Not in v1)

- Live Turbo Stream updates via filesystem watching (`.git/refs/heads/`)
- Image portability to GitHub PRs on export
- Viewed-file tracking with force-push invalidation
- Inline comments on diffs
