# Design Pass Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align Preflight's visual design with GitHub's dark-mode PR UI and break the monolithic CSS into component files.

**Architecture:** Split `application.css` (1918 lines) into 14 component files organized by UI component. Apply CSS value corrections to match GitHub's exact computed values. Make minor HTML adjustments to existing elements. Hybrid px/rem approach — px for dense UI, rem for structural elements.

**Tech Stack:** Rails 8.1 with Propshaft, plain CSS (no preprocessor), ERB templates.

**Spec:** `docs/superpowers/specs/2026-03-14-design-pass-design.md`

---

## Chunk 1: CSS File Breakup

### Task 1: Create `variables.css` and `base.css`

**Files:**
- Create: `app/assets/stylesheets/variables.css`
- Create: `app/assets/stylesheets/base.css`
- Reference: `app/assets/stylesheets/application.css` (source)

- [ ] **Step 1: Create `variables.css`**

Extract lines 1-22 from `application.css` (the `:root` block). Add the missing `--gh-font-mono` variable.

```css
:root {
  --gh-bg: #0d1117;
  --gh-canvas: #0d1117;
  --gh-canvas-subtle: #161b22;
  --gh-subtle: #161b22;
  --gh-muted: #21262d;
  --gh-border: #30363d;
  --gh-text: #c9d1d9;
  --gh-text-muted: #8b949e;
  --gh-accent: #2f81f7;
  --gh-accent-soft: rgba(56, 139, 253, 0.15);
  --gh-success: #238636;
  --gh-success-soft: rgba(35, 134, 54, 0.18);
  --gh-danger: #da3633;
  --gh-danger-soft: rgba(248, 81, 73, 0.16);
  --gh-code-add: rgba(46, 160, 67, 0.15);
  --gh-code-add-gutter: rgba(63, 185, 80, 0.3);
  --gh-code-del: rgba(248, 81, 73, 0.1);
  --gh-code-del-gutter: rgba(248, 81, 73, 0.22);
  --gh-code-hunk: rgba(56, 139, 253, 0.15);
  --gh-shadow: 0 0 0 1px rgba(48, 54, 61, 0.3);
  --gh-font-mono: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, "Liberation Mono", monospace;
}
```

- [ ] **Step 2: Create `base.css`**

Extract from `application.css`:
- Lines 24-26: `* { box-sizing }`
- Lines 28-58: `html`, `body`, `a`, `a:hover`, `button/input/select/textarea`, `code/pre`
- Lines 227-237: shared panel/card border rule (`.panel, .gh-card, .changed-file...`)
- Lines 239-314: `.panel`, `.panel-header`, `.field`, `.button`, `.button-secondary`, `.button-small`, `.errors`

Write all of these into `base.css`, preserving exact current values (corrections come in Chunk 2).

**Note:** `.sr-only` (lines 360-370) goes in `layout.css`. `.directory-actions`, `.browse-list`, `.pull-request-list`, `.browse-entry` (lines 316-355) go in `repository.css`.

- [ ] **Step 3: Verify both files are syntactically valid**

Run: `devbox run bin/rails runner "puts 'ok'"`

Expected: `ok` (confirms Rails boots, assets accessible)

---

### Task 2: Create `app-chrome.css` and `layout.css`

**Files:**
- Create: `app/assets/stylesheets/app-chrome.css`
- Create: `app/assets/stylesheets/layout.css`

- [ ] **Step 1: Create `app-chrome.css`**

Extract lines 60-131 from `application.css`:
- `.app-chrome` through `.app-chrome__link--muted`

- [ ] **Step 2: Create `layout.css`**

Extract from `application.css`:
- Lines 133-151: `.app-main`, `.page`, `.gh-page`, `.gh-page--wide`, `.page` padding
- Lines 356-358: `.gh-page` padding-top (duplicate `.gh-page` rule at line 356)
- Lines 360-370: `.sr-only`
- Lines 1869-1917: All `@media` queries (responsive breakpoints)

Place the media queries at the end of `layout.css` since they reference classes from multiple files but are primarily layout concerns.

**Note:** `.page-header` (lines 152-154) goes in `repository.css`, not here.

---

### Task 3: Create `repository.css` and `pr-header.css`

**Files:**
- Create: `app/assets/stylesheets/repository.css`
- Create: `app/assets/stylesheets/pr-header.css`

- [ ] **Step 1: Create `repository.css`**

Extract from `application.css`:
- Lines 152-154: `.page-header`
- Lines 156-197: `.gh-repository-header`, `.gh-repository-header__path`, `.gh-repository-owner`, `.gh-repository-visibility`, `.gh-repository-header__location`
- Lines 199-225: `.page-header h1`, `.page-header p`, `.page-header code`, `.eyebrow`
- Lines 316-355: `.directory-actions`, `.browse-list`, `.pull-request-list`, `.browse-entry`, `.pull-request-list li span`

- [ ] **Step 2: Create `pr-header.css`**

Extract from `application.css`:
- Lines 372-588: `.gh-breadcrumb` through `.gh-deletions`

This includes: `.gh-breadcrumb`, `.gh-pr-header`, `.gh-pr-title-row`, `.gh-pr-title-main`, `.gh-pr-title-stack`, `.gh-pr-title`, `.gh-pr-number`, `.gh-title-editor*`, `.gh-pr-meta`, `.gh-state-badge`, `.gh-pr-meta__text`, `.gh-inline-branch`, `.gh-tabs`, `.gh-tab`, `.gh-tab--active`, `.gh-tab-count`, `.gh-tab-summary`, `.gh-tab-summary__count`, `.gh-additions`, `.gh-deletions`

---

### Task 4: Create `conversation.css` and `commits.css`

**Files:**
- Create: `app/assets/stylesheets/conversation.css`
- Create: `app/assets/stylesheets/commits.css`

- [ ] **Step 1: Create `conversation.css`**

Extract from `application.css`:
- Lines 590-603: `.gh-content-with-sidebar`, `.gh-main-column`, `.gh-main-column--solo`
- Lines 605-625: `.gh-sidebar`, `.gh-sidebar-section`
- Lines 627-649: `.gh-card`, `.gh-card-header`, `.gh-card-body`
- Lines 651-658: `.markdown-body`
- Lines 660-681: `.gh-conversation-page`, `.gh-conversation-shell`, `.gh-section-header`
- Lines 683-875: `.gh-timeline` through `.gh-merge-box__body`

- [ ] **Step 2: Create `commits.css`**

Extract from `application.css`:
- Lines 877-917: `.gh-commit-list` through `.gh-commit-list__message` (conversation commit list)
- Lines 1190-1392: `.gh-commits-index` through `.gh-commit-summary__footer code`

---

### Task 5: Create `diff-table.css`, `file-tree.css`, `file-header.css`

**Files:**
- Create: `app/assets/stylesheets/diff-table.css`
- Create: `app/assets/stylesheets/file-tree.css`
- Create: `app/assets/stylesheets/file-header.css`

- [ ] **Step 1: Create `diff-table.css`**

Extract from `application.css`:
- Lines 1502-1615: `.diff-table` through `.gh-diff-table--compact .line-code code`
- Lines 1617-1687: `.gh-code-marker` through `.gh-code .o, .gh-code .p` (syntax highlighting)

- [ ] **Step 2: Create `file-tree.css`**

Extract from `application.css`:
- Lines 1061-1184: `.gh-file-tree` through `.gh-file-tree__count`
- Line 1186-1188: `.gh-diff-column`

- [ ] **Step 3: Create `file-header.css`**

Extract from `application.css`:
- Lines 1394-1500: `.changed-file` through `.gh-view-toggle-form`
- Lines 1830-1867: `.gh-view-toggle` through `.octicon`

---

### Task 6: Create `review-toolbar.css` and `inline-comments.css`

**Files:**
- Create: `app/assets/stylesheets/review-toolbar.css`
- Create: `app/assets/stylesheets/inline-comments.css`

- [ ] **Step 1: Create `review-toolbar.css`**

Extract from `application.css`:
- Lines 919-933: `.gh-comment-editor__actions`, `.gh-edit-card summary`
- Lines 935-1059: `.gh-review-toolbar` through `.gh-diff-settings__option--active`

- [ ] **Step 2: Create `inline-comments.css`**

Extract from `application.css`:
- Lines 1689-1828: `.line-code--commentable:hover` through `.inline-comment`

---

### Task 7: Rewrite `application.css` as import manifest, fix layout, and verify

**Files:**
- Modify: `app/assets/stylesheets/application.css` (replace entire contents)
- Modify: `app/views/layouts/application.html.erb:22`

- [ ] **Step 1: Change layout to use explicit stylesheet name**

In `app/views/layouts/application.html.erb`, change line 22 from:

```erb
<%= stylesheet_link_tag :app %>
```

To:

```erb
<%= stylesheet_link_tag "application" %>
```

**Why:** `stylesheet_link_tag :app` is a Propshaft shorthand that generates `<link>` tags for ALL `.css` files in the assets directory. After the split, that would load all 15 files individually (in arbitrary order) AND process the `@import` statements — causing duplicates. Using `"application"` loads only `application.css`, which then uses `@import` to pull in the others in the correct cascade order.

- [ ] **Step 2: Replace `application.css` with imports**

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

**Note:** In Propshaft development mode, assets are served at their original paths (no fingerprinting), so `@import "variables.css"` resolves to `/assets/variables.css` which Propshaft serves correctly. This is fine since Preflight is a local-only tool.

- [ ] **Step 3: Start the Rails server and verify visually**

Run: `devbox run bin/rails server`

Open `http://localhost:3000/repositories/4/pull_requests/6` — verify conversation, commits, and files views all render identically to before the split.

- [ ] **Step 4: Run the test suite**

Stop the server first, then run: `devbox run bin/rails test`

Expected: All tests pass.

- [ ] **Step 5: Commit**

```
git add app/assets/stylesheets/ app/views/layouts/application.html.erb
git commit -m "break application.css into component files"
```

---

## Chunk 2: CSS Value Corrections

### Task 8: Fix base/body values

**Files:**
- Modify: `app/assets/stylesheets/base.css`

- [ ] **Step 1: Update body styles**

In `base.css`, change the `body` rule:

```css
body {
  margin: 0;
  color: var(--gh-text);
  background: var(--gh-bg);
  font-family: -apple-system, "system-ui", "Segoe UI", "Noto Sans", Helvetica, Arial, sans-serif, "Apple Color Emoji", "Segoe UI Emoji";
  font-size: 14px;
  line-height: 1.5;
}
```

**Important:** Only `body` gets `font-size: 14px`. Do NOT change `html`. The `html` root stays at browser default (16px) so all `rem` values are unaffected.

- [ ] **Step 2: Verify in browser**

Check that the overall text size has decreased slightly and looks closer to GitHub. Check that layout elements using `rem` (page widths, sidebar widths, margins) are NOT affected.

---

### Task 9: Fix PR header values

**Files:**
- Modify: `app/assets/stylesheets/pr-header.css`

- [ ] **Step 1: Update PR title**

```css
.gh-pr-title {
  margin: 0;
  color: #f0f6fc;
  font-size: 32px;
  font-weight: 600;
  line-height: 1.5;
}
```

- [ ] **Step 2: Update PR number**

```css
.gh-pr-number {
  color: var(--gh-text-muted);
  font-size: 32px;
  font-weight: 400;
}
```

- [ ] **Step 3: Update meta text**

```css
.gh-pr-meta__text {
  color: var(--gh-text-muted);
  font-size: 14px;
}
```

- [ ] **Step 4: Update state badge**

```css
.gh-state-badge {
  display: inline-flex;
  align-items: center;
  gap: 0.3rem;
  padding: 5px 12px;
  border-radius: 999px;
  background: var(--gh-success);
  color: #fff;
  font-size: 14px;
  font-weight: 600;
}
```

- [ ] **Step 5: Update branch labels**

```css
.gh-inline-branch {
  display: inline-flex;
  align-items: center;
  padding: 2px 7px;
  border-radius: 999px;
  background: var(--gh-accent-soft);
  color: #58a6ff;
  font-family: var(--gh-font-mono);
  font-size: 12px;
  font-weight: 600;
}
```

- [ ] **Step 6: Update breadcrumb**

```css
.gh-breadcrumb {
  display: flex;
  align-items: center;
  gap: 0.45rem;
  margin: 0 0 8px;
  color: var(--gh-text-muted);
  font-size: 0.875rem;
}
```

- [ ] **Step 7: Update PR header padding**

```css
.gh-pr-header {
  padding-bottom: 8px;
}
```

- [ ] **Step 8: Update meta margin**

```css
.gh-pr-meta {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  margin-top: 8px;
  flex-wrap: wrap;
}
```

---

### Task 10: Fix tab values

**Files:**
- Modify: `app/assets/stylesheets/pr-header.css`

- [ ] **Step 1: Update tab styles**

```css
.gh-tabs {
  display: flex;
  align-items: flex-end;
  gap: 0.2rem;
  margin-top: 0;
  border-bottom: 1px solid var(--gh-border);
}

.gh-tab {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  padding: 8px 16px;
  color: var(--gh-text);
  border-bottom: 2px solid transparent;
  font-size: 14px;
  font-weight: 400;
}
```

- [ ] **Step 2: Update tab count badges**

```css
.gh-tab-count {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 20px;
  padding: 0 6px;
  border-radius: 24px;
  background: #2f3742;
  color: var(--gh-text);
  font-size: 12px;
  font-weight: 500;
}
```

- [ ] **Step 3: Update tab summary**

```css
.gh-tab-summary {
  margin-left: auto;
  display: inline-flex;
  gap: 0.75rem;
  align-items: center;
  padding-bottom: 0.85rem;
  font-size: 12px;
}
```

---

### Task 11: Fix commit list values

**Files:**
- Modify: `app/assets/stylesheets/commits.css`

- [ ] **Step 1: Update commit list item padding**

```css
.gh-commit-list-item {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 1rem;
  padding: 8px 16px;
}
```

- [ ] **Step 2: Update commit title**

```css
.gh-commit-list-item__body strong {
  display: block;
  margin-bottom: 0.25rem;
  font-size: 16px;
  font-weight: 500;
}
```

- [ ] **Step 3: Update commit group header**

```css
.gh-commit-group__header h3 {
  margin: 0;
  font-size: 14px;
  font-weight: 400;
}
```

- [ ] **Step 4: Update commit group spacing**

```css
.gh-commit-group {
  margin-bottom: 16px;
}
```

- [ ] **Step 5: Update commits index margin**

```css
.gh-commits-index {
  margin-top: 16px;
}
```

---

### Task 12: Fix diff table values

**Files:**
- Modify: `app/assets/stylesheets/diff-table.css`

- [ ] **Step 1: Update line number color**

Change `.line-number` color from `#6e7681` to `#848d97`.

- [ ] **Step 2: Update hunk background opacity**

Change `.line-number--hunk, .line-code--hunk` background from `rgba(56, 139, 253, 0.15)` to `rgba(56, 139, 253, 0.1)`.

- [ ] **Step 3: Update code left padding**

Change `.line-code code` padding from `0 8px 0 18px` to `0 8px 0 16px`.

---

### Task 13: Fix repository header spacing

**Files:**
- Modify: `app/assets/stylesheets/repository.css`

- [ ] **Step 1: Tighten repository header**

```css
.gh-repository-header {
  margin-bottom: 0;
  padding: 16px 0;
  border-bottom: 1px solid var(--gh-border);
}
```

---

### Task 14: Verify CSS corrections and commit

- [ ] **Step 1: Visual verification**

Open all three views in the browser and compare against GitHub screenshots:
- Conversation: `http://localhost:3000/repositories/4/pull_requests/6`
- Commits: `http://localhost:3000/pull_requests/6/commits`
- Files: `http://localhost:3000/repositories/4/pull_requests/6/files`

Check: font sizes, weights, padding, spacing, colors all match GitHub more closely.

- [ ] **Step 2: Run tests**

Run: `devbox run bin/rails test`

Expected: All tests pass.

- [ ] **Step 3: Commit**

```
git add app/assets/stylesheets/
git commit -m "align css values with github dark mode"
```

---

## Chunk 3: HTML Adjustments

### Task 15: Update tab summary to use diffstat blocks

**Files:**
- Modify: `app/views/pull_requests/_pull_request_header.html.erb:74-78`

- [ ] **Step 1: Replace tab summary content**

Change lines 74-78 from:

```erb
    <div class="gh-tab-summary" data-role="pr-summary">
      <span class="gh-tab-summary__count"><%= pluralize(commits_count, "commit") %></span>
      <span class="gh-additions">+<%= summary[:additions] %></span>
      <span class="gh-deletions">-<%= summary[:deletions] %></span>
    </div>
```

To:

```erb
    <div class="gh-tab-summary" data-role="pr-summary">
      <span class="gh-additions">+<%= summary[:additions] %></span>
      <span class="gh-deletions">-<%= summary[:deletions] %></span>
      <%= diffstat_blocks(summary[:additions], summary[:deletions]) %>
    </div>
```

- [ ] **Step 2: Remove orphaned CSS rule**

In `pr-header.css`, remove the `.gh-tab-summary__count` rule (it's no longer referenced).

---

### Task 16: Remove "Conversation" section heading

**Files:**
- Modify: `app/views/pull_requests/show.html.erb:14-16`

- [ ] **Step 1: Remove the section header**

Delete lines 14-16:

```erb
      <header class="gh-section-header gh-section-header--conversation">
        <h2>Conversation</h2>
      </header>
```

- [ ] **Step 2: Remove orphaned CSS**

In `conversation.css`, remove the `.gh-section-header` rules (lines 669-681 of original `application.css`) if they are no longer used anywhere else. Check first:

Run: `rg -l "gh-section-header" app/views/`

If no results, remove the CSS rules.

---

### Task 17: Final verification and commit

- [ ] **Step 1: Full visual comparison**

Open all three views and verify they match GitHub's layout more closely than before:
- Conversation: title weight, meta text size, tab sizes, no "Conversation" heading, diffstat blocks on tab row
- Commits: tighter padding, larger commit titles, correct spacing
- Files: diff code padding, line number colors, hunk background

- [ ] **Step 2: Run full test suite**

Run: `devbox run bin/rails test`

Expected: All tests pass.

- [ ] **Step 3: Commit**

```
git add app/views/ app/assets/stylesheets/
git commit -m "tighten html to match github pr layout"
```
