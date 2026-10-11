# ADR-006 :: The engine as its own library

Last updated: `2026.10.11`

> `ParrotCore` holds only the dictation engine (capture, the hotkey gesture, transcription, the dictionary, the dictation loop and delivery at the cursor) and is published as a library product, so another app can dictate with it without Parrot's interface, settings store or updater. The loop delivers through a protocol, so that app can send transcripts somewhere other than the cursor. The app parts move to a new `ParrotApp` target. Amends [ADR-001](001-core-library-and-extension-points.md), whose `ParrotCore` held every behaviour.

## 1. Decision

- **Two libraries.** `ParrotCore` is the engine and depends only on WhisperKit. `ParrotApp` holds `Settings` and `SettingsStore`, stats, the UI (the overlay included) and the Sparkle updater, and the wiring that builds the loop, and depends on `ParrotCore`. The `parrot` executable depends on `ParrotApp`; `parrot-bench` depends on `ParrotCore` only.
- **A library product.** `Package.swift` exports `ParrotCore`. Linking it compiles neither `ParrotApp` nor Sparkle.
- **The loop and its seam.** `DictationController` runs press, release and cancel through capture, transcription and the processors, then hands the text to a `TranscriptDelivery`, awaiting it. `CursorDelivery` is Parrot's: paste at the cursor with `Spacing`, copy when focus moved, discard in a password field. Another app passes its own delivery and its own `DictationObserver`s.
- **Three access levels.** `public` is the API another app uses: `HotkeyMonitor`, `Gesture`, `AudioCapture`, `Transcriber` and `TranscriptionContext`, `WhisperKitTranscriber`, `ModelRegistry`, `DictionaryStore`, `DictionaryContext`, `DictionaryProcessor`, `Transcript`, `TranscriptProcessor`, `DictationController`, `DictationObserver`, `DictationResult`, `DictationError`, `TranscriptDelivery`, `CursorDelivery`, `DeliveryError`, `InjectMode`, `FocusSnapshot` (opaque: only `capture()`), and the config, settings and dictionary paths. The rest of the engine is `package`, visible to this package's targets only. App code stays internal.
- **One model download, one dictionary.** An app linking the engine uses the same `Paths`, so it shares Parrot's downloaded models and `~/.config/parrot/dictionary`.
- **The engine reads only its own settings.** It decodes the `dictionary` key of `settings.json`, never the whole `Settings` value, which belongs to the app.

## 2. Rationale

An app that wants push-to-talk transcription would otherwise link all of `ParrotCore`, and with it Sparkle's framework, Parrot's windows and its settings store. Sparkle alone means embedding and signing another framework for no benefit.

Naming the new library `ParrotEngine` and leaving the app in `ParrotCore` was rejected: "core" already reads as the engine, the package exported no products before this, so no outside code depended on the old shape, and the engine files keep their history. The loop and cursor delivery first stayed in the app, because no other app needed them. They moved into the engine (2026.10.11) when one did: writing a second loop over the public engine parts would duplicate the press and release state machine, capture failures and the in-flight transcription rules, and the two copies would drift. Delivery became the one seam because everything before it is the same for any app; only where the text goes differs. The overlay stays in the app: an app that links the engine draws its own, so ParrotCore stays free of UI.

## 3. Design Implications

- A type becomes `public` only when an app outside this package needs it. Parrot's own targets use `package`.
- A `public` struct that other apps construct declares a `public init`, since the implicit memberwise initializer is internal.
- The engine never imports Sparkle, SwiftUI or ServiceManagement, and never reads `Settings` or `SettingsStore`. It imports AppKit only for focus, the clipboard and synthesized key events.
- `DictationController`'s `dumpWav` parameter is a `package` initializer for Parrot's `--dump-wav` flag; the public initializer leaves it off.
- Tests that cover app types import both modules.

## 4. When to Revisit

- If another app needs a different overlay hook than `DictationObserver` (audio levels while recording, say), add it as an observer method with an empty default rather than moving the overlay into the engine.
- If the engine's public API needs versioning for outside apps, tag engine releases separately from Parrot.app releases.
