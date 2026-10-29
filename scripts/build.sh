#!/usr/bin/env bash
# parrot dev build.
#   scripts/build.sh
#
# Builds the release binary, signs it with the stable "parrot-dev"
# identity, and installs it to /usr/local/bin. Signing with the same
# certificate every build keeps the TCC grants (Accessibility, mic)
# valid across rebuilds — ad-hoc signatures change on every build and
# macOS re-prompts each time.
#
# One-time setup: a self-signed code-signing cert named "parrot-dev"
# must exist in the login keychain. Create via Keychain Access →
# Certificate Assistant → Create a Certificate → type: Code Signing.

set -euo pipefail

IDENTITY="${PARROT_SIGN_IDENTITY:-parrot-dev}"
INSTALL_DIR="/usr/local/bin"
BIN_NAME="parrot"

red()    { printf "\033[31m%s\033[0m\n" "$*" >&2; }
green()  { printf "\033[32m%s\033[0m\n" "$*"; }
dim()    { printf "\033[2m%s\033[0m\n" "$*"; }

cd "$(dirname "$0")/.."

swift build -c release
BIN=".build/release/$BIN_NAME"

if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
    codesign -f -s "$IDENTITY" -i com.digimata.parrot "$BIN"
    green "✓ signed with $IDENTITY"
else
    red "signing identity '$IDENTITY' not found — keeping ad-hoc signature"
    red "macOS will re-prompt for Accessibility after this install."
fi

# mv (not cp) so the running parrot keeps its inode and isn't killed
# mid-page-in by the kernel when the signature underneath it changes.
mv -f "$BIN" "$INSTALL_DIR/$BIN_NAME"
green "✓ installed $INSTALL_DIR/$BIN_NAME"

# Restart the launch agent if installed so the new build takes over.
AGENT="com.digimata.parrot"
if launchctl print "gui/$(id -u)/$AGENT" >/dev/null 2>&1; then
    launchctl kickstart -k "gui/$(id -u)/$AGENT"
    dim "launch agent restarted"
fi
