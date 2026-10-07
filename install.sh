#!/bin/bash
# Installs the cybermod command-line tool (or, with --app, the CyberMod Studio app) from the newest GitHub release
# (release candidates included).
#
#   curl -fsSL https://raw.githubusercontent.com/jackmaxwil/cybermod-studio/main/install.sh | bash
#   curl -fsSL .../install.sh | bash -s -- --app              # CyberMod Studio.app into /Applications
#   curl -fsSL .../install.sh | bash -s -- --system           # /usr/local/bin instead of ~/.local/bin
#   curl -fsSL .../install.sh | bash -s -- --version 0.1.0    # a specific release
set -euo pipefail

REPO=jackmaxwil/cybermod-studio
DEST="$HOME/.local/bin"
VERSION=""
APP=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --system) DEST=/usr/local/bin ;;
        --app) APP=1 ;;
        --version) VERSION="${2#v}"; shift ;;
        *) echo "Unknown option: $1 (use --app, --system or --version X.Y.Z)"; exit 1 ;;
    esac
    shift
done

fail() { echo "Error: $1" >&2; echo "Next: $2" >&2; exit 1; }

[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] \
    || fail "cybermod needs a Mac with Apple silicon." "Cyberpunk 2077 for macOS runs only on Apple silicon."

if [[ -z "$VERSION" ]]; then
    # The releases API lists newest first; the first tag is the newest release, release candidates included.
    VERSION=$(curl -fsSL "https://api.github.com/repos/$REPO/releases?per_page=1" | grep -m1 '"tag_name"' \
        | sed 's/.*"v\{0,1\}\([^"]*\)".*/\1/') || true
    [[ -n "$VERSION" ]] || fail "no cybermod release found." \
        "Check https://github.com/$REPO/releases, or build from source: git clone https://github.com/$REPO && cd cybermod-studio && swift build -c release"
fi

NAME="cybermod-$VERSION-macos-arm64.tar.gz"
[[ -n "$APP" ]] && NAME="CyberModStudio-$VERSION-macos-arm64.zip"
BASE="https://github.com/$REPO/releases/download/v$VERSION"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "Downloading cybermod $VERSION ..."
curl -fsSL -o "$TMP/$NAME" "$BASE/$NAME" || fail "could not download $BASE/$NAME." "Check the version and your connection."
curl -fsSL -o "$TMP/SHA256SUMS" "$BASE/SHA256SUMS" || fail "could not download SHA256SUMS." "Check your connection and try again."
(cd "$TMP" && grep " \*\{0,1\}$NAME\$" SHA256SUMS | shasum -a 256 -c - >/dev/null) \
    || fail "checksum mismatch for $NAME; nothing was installed." "Try again; if it keeps failing, report it at https://github.com/$REPO/issues"

if [[ -n "$APP" ]]; then
    ditto -x -k "$TMP/$NAME" "$TMP/app"
    APPS=/Applications
    [[ -w "$APPS" ]] || APPS="$HOME/Applications"
    mkdir -p "$APPS"
    rm -rf "$APPS/CyberMod Studio.app"
    ditto "$TMP/app/CyberMod Studio.app" "$APPS/CyberMod Studio.app"
    # The app is not notarized; the checksum above vouches for it, so clear the download quarantine.
    xattr -dr com.apple.quarantine "$APPS/CyberMod Studio.app" 2>/dev/null || true
    echo "Installed CyberMod Studio $VERSION to $APPS/CyberMod Studio.app"
    echo "Next: open \"$APPS/CyberMod Studio.app\" and follow Get Set Up on the Play screen."
    exit 0
fi
tar -xzf "$TMP/$NAME" -C "$TMP"

SUDO=""
mkdir -p "$DEST" 2>/dev/null || true
if [[ ! -w "$DEST" ]]; then
    echo "$DEST needs administrator rights; sudo will ask for your password."
    SUDO=sudo
    $SUDO mkdir -p "$DEST"
fi
$SUDO install -m 755 "$TMP/cybermod" "$DEST/cybermod"
echo "Installed cybermod $VERSION to $DEST/cybermod"

case ":$PATH:" in
    *":$DEST:"*) echo "Next: cybermod install   (installs RED4ext for macOS into your game)" ;;
    *)
        echo "$DEST is not on your PATH. Add it (zsh):"
        echo "  echo 'export PATH=\"$DEST:\$PATH\"' >> ~/.zshrc && source ~/.zshrc"
        echo "Next: cybermod install   (installs RED4ext for macOS into your game)"
        ;;
esac
