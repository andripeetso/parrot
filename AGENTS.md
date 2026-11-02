# Notes for AI agents

## "Set this up" on a Mac

When someone asks you to set Parrot up on this Mac (it's for dictation: hold `fn`, speak, release, and the words are typed at the cursor):

1. Run `scripts/setup-mac.sh` from the repo root. It builds the app, installs `/Applications/Parrot.app`, points it at the home PC's transcription server, turns on launch at login, and opens the app. The build takes a few minutes the first time.
2. If it stops because Swift is missing, a Command Line Tools window has opened. Ask the person to click **Install** and wait for it to finish, then run the script again.
3. When it finishes, walk the person through the steps it prints. Only they can click these: Microphone and Accessibility access, and Login Items if macOS asks. Parrot's welcome window guides them.
4. Check it worked: `tail -30 ~/Library/Logs/parrot/parrot.err.log` should show `✓ server reachable` (at home) and, once they've dictated once, a `⏱ … release→text` line. Never print or read what they said: recordings and transcripts in `~/Library/Application Support/parrot/` are private.

Good to know:

- The server is the omarchy PC at `http://192.168.8.237:7886/api/transcribe`, on the home Wi-Fi "Jacinto". Away from home, or with the PC off, Parrot falls back to its on-device model by itself, so "server not reachable" is not an error.
- The hotkey on a laptop is `fn`. F13 (tap to talk), F14 (History), F15 (file drop) and F16 (cancel) need an external keyboard that has them. Settings (⌘, in Parrot's menu) changes keys.
- The app is ad-hoc signed, so after a rebuild macOS may ask for Accessibility again: remove Parrot from the Accessibility list and add it back.
- Don't change the server address, the hotkey, or the model unless the person asks.

## Working on the code

`swift build`, `swift test`, then `scripts/build-app.sh 0.2.0-andri` for the app. See README.md. The PC's server lives in `server/parrot-asr/`.
