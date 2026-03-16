# Add Repository Page Redesign

## Problem

Adding a repository to Preflight requires either typing a full filesystem path manually or clicking through directories one level at a time on a separate browse page. Both approaches create unnecessary friction.

## Solution

Merge `/repositories/new` and `/browse` into a single page that auto-discovers git repositories from `~/Code` and presents them as a one-click pick list. Manual path entry and directory browsing remain available as fallbacks on the same page.

## Design

### Page modes

The `/repositories/new` page operates in two modes, toggled by the presence of a `directory` query param:

**Discovery mode** (default, no param):
- Toolbar row: "Add repository" heading (24px, weight 400) + "Cancel" button (links to root)
- List of git repos found in `~/Code` not already added to Preflight, displayed in `.pf-repo-list` pattern: `octicon(:repo)` icon, bold name, monospace path, and an "Add" button per row
- When `~/Code` doesn't exist or has no git repos: "No git repositories found in ~/Code" with a "Browse folders" link to `?directory=` + `Dir.home`
- When `~/Code` has repos but all are already added: "All repositories in ~/Code have been added" with the same "Browse folders" link
- Collapsed `<details>` element at bottom labeled "Add by path" — expands to show path field, optional name field, and submit button

**Browse mode** (`?directory=/some/path`):
- Same toolbar: "Add repository" + "Cancel"
- "Back to discovered repositories" link (always shown in browse mode, links to `new_repository_path` with no param)
- Breadcrumb nav from path segments using `.pf-browse-breadcrumb` pattern — all segment links use `new_repository_path(directory: ...)` instead of `browse_path`
- Directory listing in `.pf-repo-list`: git repos get `octicon(:repo)` + "Add" button, plain directories get `octicon(:file_directory)` + "Open" link — "Open" links use `new_repository_path(directory: ...)`
- Same collapsed `<details>` "Add by path" at bottom

### Route changes

- `/browse` route kept but controller action redirects to `/repositories/new?directory=...`
- `resources :repositories` already has `:new` — no route changes needed

### Controller changes (`local_repositories_controller.rb`)

- `new` action: builds `@local_repository`, calls `discover_repositories` to scan `~/Code` into `@discovered_repos`, optionally loads `@directory`/`@entries` when `directory` param present. Rescues `Errno::ENOENT` by redirecting to `new_repository_path` with an alert.
- `browse` action: redirects to `new_repository_path(directory: params[:directory])`
- `create` action: on failure, calls `discover_repositories` and conditionally loads `@directory`/`@entries` (same as `new`) before `render :new`. Extract shared setup into a `load_new_page_data` private method called by both `new` and the `create` failure path.
- New private method `discover_repositories`: hardcoded to scan `~/Code` one level deep for git repos, filters out paths already in `LocalRepository`, returns sorted `BrowseEntry` list. Returns `[]` if `~/Code` doesn't exist.
- `@parent_directory` is dropped — breadcrumb navigation replaces "Up one level"
- Existing `directory_entries` method stays for browse mode

### View changes

- `new.html.erb`: full rewrite to handle both modes (discovery list vs directory browser) with shared `<details>` manual input
- `browse.html.erb`: deleted — `new.html.erb` handles everything
- `index.html.erb`: empty state "Browse folders" link updated to `new_repository_path` (no directory param — sends user to discovery mode)

### CSS additions

- `.pf-details-manual` — styling for the collapsed manual-add `<details>` element (summary styling, open state padding)
- No new list styles needed — reuses existing `.pf-repo-list` family and `.pf-browse-breadcrumb`

### Test changes (`local_repositories_flow_test.rb`)

- Browse test: updated to follow redirect from `/browse` to `/repositories/new?directory=...`, assertion updated for new heading text
- Registration test: already uses `new_repository_path`, no change needed

## Files to modify

| File | Change |
|------|--------|
| `app/controllers/local_repositories_controller.rb` | Rewrite `new`, simplify `browse` to redirect, update `create` failure path, add `discover_repositories` and `load_new_page_data` |
| `app/views/local_repositories/new.html.erb` | Full rewrite — discovery + browse + manual input |
| `app/views/local_repositories/browse.html.erb` | Delete |
| `app/views/local_repositories/index.html.erb` | Update empty state link |
| `app/assets/stylesheets/repository.css` | Add `.pf-details-manual` styles |
| `test/integration/local_repositories_flow_test.rb` | Update browse test |

## Verification

1. `devbox run -- bin/rails test` — all tests pass
2. Visit `/repositories/new` — shows discovered repos from ~/Code with Add buttons
3. Click "Add" on a discovered repo — creates it, redirects to pulls page
4. Visit `/repositories/new` again — that repo no longer appears in discovered list
5. Visit `/browse?directory=...` — redirects to `/repositories/new?directory=...`
6. Browse mode shows breadcrumb + directory listing with "Back to discovered repositories" link
7. Collapsed "Add by path" expands and submits correctly
8. When all ~/Code repos added, shows "All repositories in ~/Code have been added" with browse link
9. When ~/Code doesn't exist, shows "No git repositories found in ~/Code" with browse link
