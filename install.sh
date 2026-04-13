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
