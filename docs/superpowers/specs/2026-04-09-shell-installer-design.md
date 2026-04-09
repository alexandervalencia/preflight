# Shell Script Installer Design

**Date:** 2026-04-09
**Status:** Approved

## Problem

Preflight is currently distributed via Homebrew. Company teams are moving away from Homebrew as a standard tool. Users need a way to install Preflight without it.

## Goals

- Mac-only installer (darwin-arm64, darwin-amd64)
- No Homebrew required
- Single prerequisite: devbox (already company standard)
- Install and upgrade via the same script
- Everything lives in `~/.preflight/` for easy cleanup

## Non-Goals

- Linux support
- Bundling Ruby or gems into the release artifacts
- A separate uninstall script

---

## Architecture

### Install layout

```
~/.preflight/
  bin/
    preflight          ← Go CLI binary
  libexec/
    bin/
      start-server     ← updated: uses devbox run (not Homebrew ruby)
      run-rails        ← updated: same
    server/            ← Rails app extracted from server tarball
      devbox.json      ← minimal runtime devbox config (ruby@3.4 only)
      Gemfile
      Gemfile.lock
      ...
    vendor/
      bundle/          ← gems vendored here by install script
  db.sqlite3           ← user data (untouched on upgrade)
  preflight.log
  preflight.pid
```

The `manager.go` production code path is **unchanged** — it still looks for `libexec/bin/start-server` relative to the binary, which continues to work with this layout.

### Ruby runtime

`start-server` and `run-rails` drop the Homebrew Ruby lookup and instead invoke:

```bash
devbox run --config "$LIBEXEC_DIR/server/devbox.json" -- bundle exec rails ...
```

The server's `devbox.json` is a minimal config declaring only `ruby@3.4` — not the full project devbox.json, which includes the entire dev toolchain.

---

## Components

### 1. `script/runtime-devbox.json`

A new minimal devbox config for the server runtime:

```json
{
  "packages": ["ruby@3.4"],
  "shell": { "init_hook": [] }
}
```

This is copied into the server tarball as `devbox.json` during CI packaging.

### 2. Updated `script/start-server` and `script/run-rails`

Remove the Homebrew Ruby lookup block. Replace with a single `devbox run` invocation using the server's own `devbox.json`. Both scripts already resolve `LIBEXEC_DIR` correctly, so they know where the config lives.

### 3. `install.sh` (new, at repo root)

Served via GitHub raw content:
```
curl -fsSL https://raw.githubusercontent.com/alexandervalencia/preflight/main/install.sh | bash
```

#### Script flow

```
1. Preflight checks
   - macOS only (uname -s must be Darwin)
   - Detect arch: arm64 → darwin-arm64, x86_64 → darwin-amd64
   - devbox in PATH? If not: print install URL + exit 1

2. Resolve version
   - Default: fetch latest tag from GitHub Releases API
   - Override: PREFLIGHT_VERSION env var for pinning

3. Download (to mktemp dir, cleaned up on EXIT trap)
   - preflight-<arch>.tar.gz
   - preflight-server-<version>.tar.gz

4. Install
   - Preserve user data: db.sqlite3, preflight.log are never touched
   - Atomic libexec replacement:
       mv ~/.preflight/libexec → ~/.preflight/libexec.bak
       extract new libexec
       rm -rf libexec.bak  (only on success)
   - Extract CLI binary → ~/.preflight/bin/preflight
   - chmod +x the binary
   - Run: devbox run --config ~/.preflight/libexec/server/devbox.json \
            -- bundle install --deployment --path ../vendor/bundle --quiet

5. PATH setup
   - Skip if ~/.preflight/bin is already in PATH
   - Detect shell via $SHELL: zsh → ~/.zshrc, bash → ~/.bashrc, unknown → print manual instruction
   - Append: export PATH="$HOME/.preflight/bin:$PATH"
   - Print reload reminder

6. Smoke check
   - Run ~/.preflight/bin/preflight --version

7. Print success
   - Confirm installed version
   - Print uninstall one-liner: rm -rf ~/.preflight + PATH line removal
```

### 4. `release.yml` update

In the "Package server" step, add one line before creating the tarball:

```bash
cp script/runtime-devbox.json dist/server-package/server/devbox.json
```

This ensures the minimal runtime devbox config ships with every release. No other CI changes — no macOS runners, no gem pre-bundling.

---

## Error Handling

- `set -euo pipefail` — any unexpected failure exits immediately
- `curl -fsSL` — `-f` flag turns HTTP 4xx/5xx into non-zero exit
- Temp dir cleaned via EXIT trap regardless of success or failure
- Failed bundle install: `libexec.bak` is left in place; user re-runs the installer to retry
- Version resolution failure: exits with instructions to set `PREFLIGHT_VERSION` explicitly
- Arch/OS mismatch: clear error message + exit 1 before any downloads

## Upgrade Behavior

Running the installer again on an existing install is fully idempotent — it always performs the same atomic libexec swap and binary replacement. No version comparison is done; the script simply installs the resolved version. User data (`db.sqlite3`, `preflight.log`, `preflight.pid`) is never touched.

## Testing the Installer

The script can be tested locally without curl:

```bash
bash install.sh
PREFLIGHT_VERSION=v0.2.0 bash install.sh  # pin a specific version
```

No changes to the Go test suite are required since `manager.go`'s production code path is unchanged.
