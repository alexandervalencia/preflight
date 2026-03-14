# Design Pass: Align Preflight with GitHub's PR UI

## Goal

Tighten Preflight's visual design to match GitHub's dark-mode PR review UI. Polish existing features only — no new features. Break the monolithic 1918-line `application.css` into component-based files.

## Scope

- **In scope:** CSS value corrections (fonts, colors, sizes, margins, padding), CSS file restructuring, minor HTML adjustments to existing elements
- **Out of scope:** Adding features Preflight doesn't have (e.g., conversation sidebar, repo-level nav tabs, "Owner" badges, Checks tab)

## Approach: Hybrid px/rem

- **px** for dense UI components: diff tables, tabs, file headers, file tree, line numbers, toolbar buttons
- **rem** for structural elements: page widths, margins, PR title, layout grids

---

## Part 1: CSS File Breakup

Split `application.css` into 14 component files. `application.css` becomes a manifest of imports.

```
app/assets/stylesheets/
  application.css          # @import statements only
  variables.css            # CSS custom properties (colors, shadows)
  base.css                 # resets, body, links, form elements, code/pre
  app-chrome.css           # top navigation bar (.app-chrome, .brand, etc.)
  layout.css               # .page, .gh-page, .gh-page--wide, .sr-only, media queries
  repository.css           # .gh-repository-header, .page-header, .browse-list, .pull-request-list, .eyebrow
  pr-header.css            # .gh-pr-header, .gh-pr-title, .gh-pr-meta, .gh-state-badge, .gh-tabs, .gh-inline-branch, .gh-title-editor
  conversation.css         # .gh-conversation-*, .gh-timeline, .gh-comment-card, .gh-merge-box, .gh-markdown-body, .gh-md-*
  commits.css              # .gh-commits-index, .gh-commit-group, .gh-commit-list-item, .gh-commit-summary, .gh-verified
  diff-table.css           # .diff-table, .line-number, .line-code, .gh-code-marker, .gh-code (syntax), .gh-split-diff, .gh-unified-diff, .gh-diff-table--compact
  file-tree.css            # .gh-file-tree, .gh-file-filter, .gh-file-tree__*
  file-header.css          # .changed-file, .gh-file-header, .gh-file-stats, .gh-diffstat, .gh-view-toggle, .file-review-tools
  review-toolbar.css       # .gh-review-toolbar, .gh-toolbar-button, .gh-diff-settings, .gh-viewed-summary
  inline-comments.css      # .gh-inline-comment, .gh-inline-menu, .inline-comment-form, .comment-row, .line-menu
```

### Import order in application.css

```css
/* Variables & Base */
@import "variables.css";
@import "base.css";

/* Layout & Chrome */
@import "app-chrome.css";
@import "layout.css";

/* Pages */
@import "repository.css";
@import "pr-header.css";
@import "conversation.css";
@import "commits.css";

/* Review UI */
@import "review-toolbar.css";
@import "file-tree.css";
@import "file-header.css";
@import "diff-table.css";
@import "inline-comments.css";
```

---

## Part 2: CSS Value Corrections

All values below come from GitHub's computed styles in dark mode, extracted via Playwright.

### Body / Base

| Property | Current | Target | Notes |
|----------|---------|--------|-------|
| `body` font-family | `ui-sans-serif, -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif` | `-apple-system, "system-ui", "Segoe UI", "Noto Sans", Helvetica, Arial, sans-serif, "Apple Color Emoji", "Segoe UI Emoji"` | Match GitHub's stack exactly |
| `body` font-size | unset (browser 16px) | `14px` | GitHub's base size |
| `body` line-height | unset | `1.5` | 21px at 14px base |

### PR Title (`.gh-pr-title`)

| Property | Current | Target |
|----------|---------|--------|
| font-weight | `500` | `600` |
| font-size | `2rem` | `2rem` (32px at 16px, but with 14px base this becomes 28px — use `32px` explicitly) |
| line-height | `1.5` | `1.5` |

### PR Number (`.gh-pr-number`)

| Property | Current | Target |
|----------|---------|--------|
| font-size | `2rem` | `32px` (same fix as title) |

### Tabs (`.gh-tab`)

| Property | Current | Target |
|----------|---------|--------|
| font-size | `0.9rem` | `14px` |
| padding | `0.85rem 1rem` | `8px 16px` |
| font-weight | `500` | `400` |
| gap (between icon and text) | `0.45rem` | `8px` |

### Tab Count Badges (`.gh-tab-count`)

| Property | Current | Target |
|----------|---------|--------|
| font-size | `0.75rem` | `12px` |
| background | `rgba(110, 118, 129, 0.22)` | `#2f3742` |
| padding | `0.05rem 0.35rem` | `0 6px` |
| font-weight | `600` | `500` |
| min-width | `1.35rem` | `20px` |
| border-radius | `999px` | `24px` |

### Tab Summary (`.gh-tab-summary`)

| Property | Current | Target |
|----------|---------|--------|
| font-size | `0.875rem` | `12px` |

### Meta Text (`.gh-pr-meta__text`)

| Property | Current | Target |
|----------|---------|--------|
| font-size | `0.95rem` | `14px` |

### State Badge (`.gh-state-badge`)

| Property | Current | Target |
|----------|---------|--------|
| font-size | `0.875rem` | `14px` |
| padding | `0.32rem 0.7rem` | `5px 12px` |

### Branch Labels (`.gh-inline-branch`)

| Property | Current | Target |
|----------|---------|--------|
| font-size | `0.82rem` | `12px` |
| padding | `0.12rem 0.45rem` | `2px 7px` |
| font-weight | `600` | `600` (keep) |

### Commit List Items (`.gh-commit-list-item`)

| Property | Current | Target |
|----------|---------|--------|
| padding | `1rem` | `8px 16px` |

### Commit Title (`.gh-commit-list-item__body strong`)

| Property | Current | Target |
|----------|---------|--------|
| font-size | `0.875rem` | `16px` |
| font-weight | `600` | `500` |

### Commit Group Heading (`.gh-commit-group__header h3`)

| Property | Current | Target |
|----------|---------|--------|
| font-size | `0.875rem` | `14px` |

### Diff Table

| Property | Current | Target |
|----------|---------|--------|
| `.line-number` color | `#6e7681` | `#848d97` |
| hunk bg (`.line-code--hunk`) | `rgba(56, 139, 253, 0.15)` | `rgba(56, 139, 253, 0.1)` |
| code left padding | `18px` | `16px` |

### Spacing Tightening

| Element | Current | Target | Notes |
|---------|---------|--------|-------|
| `.gh-repository-header` margin-bottom | `1.5rem` | `0` | Let padding handle it |
| `.gh-repository-header` padding | `1rem 0 0` | `16px 0` | Tighter |
| `.gh-breadcrumb` margin-bottom | `0.85rem` | `8px` | Tighter |
| `.gh-pr-header` padding-bottom | `1rem` | `8px` | Tighter |
| `.gh-pr-meta` margin-top | `0.9rem` | `8px` | |
| `.gh-tabs` margin-top | `1.1rem` | `0` | Tabs follow meta directly, border creates separation |
| `.gh-commits-index` margin-top | `1rem` | `16px` | |
| `.gh-commit-group` margin-bottom | `1.5rem` | `16px` | |

---

## Part 3: HTML Adjustments

### 3a. Diffstat blocks on tab row

**File:** `app/views/pull_requests/_pull_request_header.html.erb`

Replace the text-only summary (`3 commits +23 -4`) with the `+23 -4 █████` format using the existing `diffstat_blocks` helper.

Before:
```
3 commits  +23  -4
```

After:
```
+23  -4  █████
```

### 3b. Remove "Conversation" section heading

**File:** `app/views/pull_requests/show.html.erb`

Remove the `<h2>Conversation</h2>` section header. GitHub flows directly from tabs into the timeline without an intermediate heading.

### 3c. Repository header tightening

**File:** `app/views/pull_requests/_pull_request_header.html.erb` (and potentially `_repository_header.html.erb`)

Reduce vertical spacing between repo header, breadcrumb, and PR title. This is primarily CSS margin/padding changes, but may involve removing unnecessary wrapper `<div>`s if they add unwanted spacing.

---

## Verification

After implementation:
1. Start the Rails server (`devbox run bin/rails server`)
2. Navigate to the rails PR at `http://localhost:3000/repositories/4/pull_requests/6`
3. Compare conversation, commits, and files changed views against GitHub screenshots saved in `.superpowers/brainstorm/`
4. Verify no visual regressions on other repositories
5. Run existing test suite (`devbox run bin/rails test`)
