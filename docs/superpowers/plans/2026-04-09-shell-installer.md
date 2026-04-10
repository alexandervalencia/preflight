# Shell Script Installer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Homebrew tap distribution with a `curl | bash` installer that requires only devbox as a prerequisite.

**Architecture:** A `script/runtime-devbox.json` provides a minimal devbox config (ruby@3.4 only) that ships inside the server tarball. The `start-server` and `run-rails` scripts drop the Homebrew Ruby lookup and call `devbox run --config` instead. An `install.sh` at the repo root downloads both release tarballs, extracts them to `~/.preflight/`, and runs `bundle install` via devbox to vendor gems.

**Tech Stack:** bash, devbox, Bundler, GoReleaser (existing), GitHub Actions (existing)

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `script/runtime-devbox.json` | Minimal devbox config declaring ruby@3.4 for production server |
| Modify | `script/start-server` | Remove Homebrew Ruby lookup; use `devbox run --config` |
| Modify | `script/run-rails` | Same change as start-server |
| Modify | `.github/workflows/release.yml` | Copy runtime-devbox.json into server package before tarball creation |
| Create | `install.sh` | curl-pipe-bash installer: download, extract, bundle, PATH setup |

`manager.go` is **not modified** — the production code path (`findServerCommand`) already resolves `libexec/bin/start-server` relative to the binary, which continues to work.

---

### Task 1: Add `script/runtime-devbox.json`

**Files:**
- Create: `script/runtime-devbox.json`

- [ ] **Step 1: Create the file**

```json
{
  "packages": ["ruby@3.4"],
  "shell": {
    "init_hook": []
  }
}
```

Save to `script/runtime-devbox.json`.

- [ ] **Step 2: Verify it is valid JSON**

Run:
```bash
python3 -m json.tool script/runtime-devbox.json
```

Expected output: the formatted JSON printed to stdout, exit 0.

- [ ] **Step 3: Commit**

```bash
git add script/runtime-devbox.json
git commit -m "add runtime devbox config for shell installer"
```

---

### Task 2: Update `script/start-server` to use devbox

**Files:**
- Modify: `script/start-server`

- [ ] **Step 1: Replace the file contents**

The current file prefers Homebrew Ruby. Replace it entirely with this version that uses `devbox run` instead:

```bash
#!/usr/bin/env bash
set -e

# Resolve the directory where this script lives
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIBEXEC_DIR="$(dirname "$SCRIPT_DIR")"

export BUNDLE_GEMFILE="$LIBEXEC_DIR/server/Gemfile"
export BUNDLE_PATH="$LIBEXEC_DIR/vendor/bundle"
export GEM_HOME="$LIBEXEC_DIR/vendor/bundle"

export RAILS_ENV="${RAILS_ENV:-production}"
export SECRET_KEY_BASE="${SECRET_KEY_BASE:-preflight-local-development-only}"

cd "$LIBEXEC_DIR/server"
exec devbox run --config "$LIBEXEC_DIR/server/devbox.json" -- bundle exec rails server "$@"
```

- [ ] **Step 2: Verify shell syntax**

Run:
```bash
bash -n script/start-server
```

Expected: no output, exit 0.

- [ ] **Step 3: Commit**

```bash
git add script/start-server
git commit -m "update start-server to use devbox instead of homebrew ruby"
```

---

### Task 3: Update `script/run-rails` to use devbox

**Files:**
- Modify: `script/run-rails`

- [ ] **Step 1: Replace the file contents**

```bash
#!/usr/bin/env bash
set -e

# Run an arbitrary bin/rails command with the correct Ruby and bundle env.
# Usage: run-rails db:prepare
#        run-rails runner "puts 1"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIBEXEC_DIR="$(dirname "$SCRIPT_DIR")"

export BUNDLE_GEMFILE="$LIBEXEC_DIR/server/Gemfile"
export BUNDLE_PATH="$LIBEXEC_DIR/vendor/bundle"
export GEM_HOME="$LIBEXEC_DIR/vendor/bundle"

export RAILS_ENV="${RAILS_ENV:-production}"
export SECRET_KEY_BASE="${SECRET_KEY_BASE:-preflight-local-development-only}"

cd "$LIBEXEC_DIR/server"
exec devbox run --config "$LIBEXEC_DIR/server/devbox.json" -- bundle exec rails "$@"
```

- [ ] **Step 2: Verify shell syntax**

Run:
```bash
bash -n script/run-rails
```

Expected: no output, exit 0.

- [ ] **Step 3: Commit**

```bash
git add script/run-rails
git commit -m "update run-rails to use devbox instead of homebrew ruby"
```

---

### Task 4: Update `release.yml` to include `runtime-devbox.json` in the server tarball

**Files:**
- Modify: `.github/workflows/release.yml`

- [ ] **Step 1: Add the copy step**

In the "Package server" step, add one line immediately before the `tar czf` command:

```yaml
      - name: Package server
        run: |
          VERSION="${GITHUB_REF#refs/tags/}"
          mkdir -p dist/server-package/bin dist/server-package/server

          # Copy the Rails app (excluding dev/test artifacts)
          rsync -a --exclude='.git' --exclude='tmp/' --exclude='log/' \
            --exclude='storage/' --exclude='cli/' --exclude='dist/' \
            --exclude='.superpowers/' --exclude='vendor/bundle/' \
            --exclude='.devbox/' --exclude='node_modules/' \
            --exclude='test/' --exclude='.goreleaser.yml' \
            --exclude='.github/' \
            . dist/server-package/server/

          # Copy the server scripts
          cp script/start-server dist/server-package/bin/start-server
          cp script/run-rails dist/server-package/bin/run-rails
          chmod +x dist/server-package/bin/start-server dist/server-package/bin/run-rails

          # Copy the minimal runtime devbox config
          cp script/runtime-devbox.json dist/server-package/server/devbox.json

          # Create the tarball
          cd dist
          tar czf "preflight-server-${VERSION}.tar.gz" -C server-package .
```

The only new line is the `cp script/runtime-devbox.json dist/server-package/server/devbox.json` before the `cd dist` line.

- [ ] **Step 2: Verify the YAML is valid**

Run:
```bash
python3 -c "import yaml, sys; yaml.safe_load(open('.github/workflows/release.yml'))" && echo "valid"
```

Expected: `valid`, exit 0.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "include runtime devbox config in server release package"
```

---

### Task 5: Write `install.sh`

**Files:**
- Create: `install.sh`

- [ ] **Step 1: Create the installer script**

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO="alexandervalencia/preflight"
INSTALL_DIR="$HOME/.preflight"
VERSION="${PREFLIGHT_VERSION:-}"

# ── preflight checks ──────────────────────────────────────────────────────────

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Error: this installer only supports macOS." >&2
  exit 1
fi

case "$(uname -m)" in
  arm64)   ARCH="darwin-arm64" ;;
  x86_64)  ARCH="darwin-amd64" ;;
  *)
    echo "Error: unsupported architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

if ! command -v devbox &>/dev/null; then
  echo "Error: devbox is required but not installed." >&2
  echo "Install it from: https://www.jetify.com/devbox/docs/installing_devbox/" >&2
  exit 1
fi

# ── resolve version ───────────────────────────────────────────────────────────

if [[ -z "$VERSION" ]]; then
  VERSION="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
    | grep '"tag_name"' \
    | cut -d'"' -f4)"
  if [[ -z "$VERSION" ]]; then
    echo "Error: could not determine latest version." >&2
    echo "Set PREFLIGHT_VERSION to install a specific version, e.g.:" >&2
    echo "  PREFLIGHT_VERSION=v0.2.0 bash install.sh" >&2
    exit 1
  fi
fi

echo "Installing preflight $VERSION..."

# ── download ──────────────────────────────────────────────────────────────────

TMP_DIR="$(mktemp -d)"
INSTALL_OK=false

cleanup() {
  if [[ "$INSTALL_OK" == false && -d "$INSTALL_DIR/libexec.bak" ]]; then
    echo "Install failed — restoring previous install..." >&2
    rm -rf "$INSTALL_DIR/libexec"
    mv "$INSTALL_DIR/libexec.bak" "$INSTALL_DIR/libexec"
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

BASE_URL="https://github.com/$REPO/releases/download/$VERSION"
CLI_TARBALL="preflight-$ARCH.tar.gz"
SERVER_TARBALL="preflight-server-$VERSION.tar.gz"

echo "Downloading CLI binary..."
curl -fsSL "$BASE_URL/$CLI_TARBALL" -o "$TMP_DIR/$CLI_TARBALL"

echo "Downloading server package..."
curl -fsSL "$BASE_URL/$SERVER_TARBALL" -o "$TMP_DIR/$SERVER_TARBALL"

# ── install ───────────────────────────────────────────────────────────────────

mkdir -p "$INSTALL_DIR/bin"

# Atomic libexec replacement: back up existing, restore on failure
if [[ -d "$INSTALL_DIR/libexec" ]]; then
  mv "$INSTALL_DIR/libexec" "$INSTALL_DIR/libexec.bak"
fi

echo "Extracting server package..."
mkdir -p "$INSTALL_DIR/libexec"
tar -xzf "$TMP_DIR/$SERVER_TARBALL" -C "$INSTALL_DIR/libexec"

echo "Extracting CLI binary..."
mkdir -p "$TMP_DIR/cli"
tar -xzf "$TMP_DIR/$CLI_TARBALL" -C "$TMP_DIR/cli"
cp "$TMP_DIR/cli/preflight" "$INSTALL_DIR/bin/preflight"
chmod +x "$INSTALL_DIR/bin/preflight"

echo "Installing gem dependencies (this may take a few minutes on first install)..."
BUNDLE_GEMFILE="$INSTALL_DIR/libexec/server/Gemfile" \
BUNDLE_PATH="$INSTALL_DIR/libexec/vendor/bundle" \
GEM_HOME="$INSTALL_DIR/libexec/vendor/bundle" \
devbox run --config "$INSTALL_DIR/libexec/server/devbox.json" \
  -- bundle install --quiet

# Success — remove the backup
rm -rf "$INSTALL_DIR/libexec.bak"
INSTALL_OK=true

# ── PATH setup ────────────────────────────────────────────────────────────────

PATH_LINE='export PATH="$HOME/.preflight/bin:$PATH"'
SHELL_RC=""

if [[ ":$PATH:" != *":$INSTALL_DIR/bin:"* ]]; then
  case "${SHELL:-}" in
    */zsh)
      SHELL_RC="$HOME/.zshrc"
      ;;
    */bash)
      SHELL_RC="$HOME/.bashrc"
      ;;
    *)
      echo ""
      echo "Add ~/.preflight/bin to your PATH manually:"
      echo "  $PATH_LINE"
      ;;
  esac

  if [[ -n "$SHELL_RC" ]]; then
    if ! grep -qF '.preflight/bin' "$SHELL_RC" 2>/dev/null; then
      printf '\n# Added by preflight installer\n%s\n' "$PATH_LINE" >> "$SHELL_RC"
      echo "Added ~/.preflight/bin to PATH in $SHELL_RC"
      echo "Run: source $SHELL_RC"
    else
      echo "~/.preflight/bin already in $SHELL_RC"
    fi
  fi
fi

# ── smoke check ───────────────────────────────────────────────────────────────

if ! "$INSTALL_DIR/bin/preflight" help &>/dev/null; then
  echo "Warning: smoke check failed — the binary may not work correctly." >&2
fi

# ── success ───────────────────────────────────────────────────────────────────

echo ""
echo "preflight $VERSION installed to ~/.preflight"
echo ""
echo "To uninstall:"
echo "  rm -rf ~/.preflight"
if [[ -n "$SHELL_RC" ]]; then
  echo "  Remove the PATH export line from $SHELL_RC"
fi
```

- [ ] **Step 2: Verify shell syntax**

Run:
```bash
bash -n install.sh
```

Expected: no output, exit 0.

- [ ] **Step 3: Run shellcheck if available**

Run:
```bash
if command -v shellcheck &>/dev/null; then
  shellcheck install.sh
  echo "shellcheck passed"
else
  echo "shellcheck not installed — skipping"
fi
```

Expected: either `shellcheck passed` or `shellcheck not installed — skipping`, exit 0.

- [ ] **Step 4: Commit**

```bash
git add install.sh
git commit -m "add curl-pipe-bash installer for mac without homebrew"
```

---

## Testing the Full Flow

Once all tasks are committed, verify end-to-end with a real release tag by running locally:

```bash
# Test with a pinned version
PREFLIGHT_VERSION=v0.x.y bash install.sh

# Verify binary works
~/.preflight/bin/preflight help

# Verify server starts (requires the full release artifacts to be on GitHub)
~/.preflight/bin/preflight server start
```

To test upgrades, run `bash install.sh` a second time — it should complete without touching `db.sqlite3`.
