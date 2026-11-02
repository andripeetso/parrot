#!/usr/bin/env bash
# Sets Parrot up on another Mac in the house: builds it here, installs it in
# /Applications, points it at the PC's transcription server, and starts it
# at login. Safe to run again; it rebuilds and keeps the settings.
#   scripts/setup-mac.sh
#
#   PARROT_SERVER   transcription server URL
#                   (default: the omarchy PC, http://192.168.8.237:7886/api/transcribe)
#
# Away from home, or with the PC off, Parrot uses its on-device model.
# Built here, so Gatekeeper never blocks it; ad-hoc signed, so rebuilding
# means granting Accessibility again.

set -euo pipefail
cd "$(dirname "$0")/.."

SERVER="${PARROT_SERVER:-http://192.168.8.237:7886/api/transcribe}"
SETTINGS="${XDG_CONFIG_HOME:-$HOME/.config}/parrot/settings.json"

[ "$(uname -m)" = arm64 ] || { echo "! Parrot needs an Apple Silicon Mac (M1 or newer)."; exit 1; }
[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 14 ] || { echo "! Parrot needs macOS 14 or newer."; exit 1; }
if ! xcrun --find swift >/dev/null 2>&1; then
    echo "! Swift is missing. Click Install in the window that opens (Command Line Tools,"
    echo "  about 10 minutes), then run this script again."
    xcode-select --install || true
    exit 1
fi

# A non-numeric version suffix switches off the updater, which would
# otherwise replace this build with an upstream release.
PARROT_TIMESTAMP=none scripts/build-app.sh 0.2.0-andri

echo "→ installing /Applications/Parrot.app"
osascript -e 'quit app "Parrot"' 2>/dev/null || true
pkill -x parrot 2>/dev/null || true
sleep 1
# Removed first, not overwritten: macOS kills a signed binary replaced in place.
rm -rf /Applications/Parrot.app
ditto build/Parrot.app /Applications/Parrot.app

echo "→ server: $SERVER"
mkdir -p "$(dirname "$SETTINGS")"
if [ -s "$SETTINGS" ]; then
    # Only the server changes; Parrot reloads the file when it is edited.
    plutil -extract extras json -o /dev/null "$SETTINGS" 2>/dev/null || plutil -insert extras -dictionary "$SETTINGS"
    plutil -replace extras.server -string "$SERVER" "$SETTINGS"
else
    # Not via plutil: it reads a bare {} as an old-style plist and can't write it back.
    printf '{"extras":{"server":"%s"}}\n' "$SERVER" > "$SETTINGS"
fi
if curl -fsS --max-time 3 "${SERVER%/api/transcribe}/health" >/dev/null; then
    echo "✓ server reachable"
else
    echo "! server not reachable right now; Parrot uses the on-device model until it is."
fi

# Registers the login item and opens the app.
/Applications/Parrot.app/Contents/MacOS/parrot install --launch-at-login

cat <<'EOF'

✓ Parrot is installed. On this Mac, a person now needs to:
  1. Follow Parrot's welcome window: allow Microphone and Accessibility
     (System Settings → Privacy & Security → Accessibility → turn on Parrot).
     It then downloads its on-device model (about 150 MB).
  2. If asked, allow Parrot under System Settings → General → Login Items.
  3. Try it: click into a text field, hold fn, speak, let go.
EOF
