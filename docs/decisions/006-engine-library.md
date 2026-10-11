# ADR-006 :: The engine as its own library

Last updated: `2026.10.10`

> `ParrotCore` holds only the dictation engine (capture, the hotkey gesture, transcription, the dictionary) and is published as a library product, so another app can dictate with it without Parrot's interface, settings store or updater. The app parts move to a new `ParrotApp` target. Amends [ADR-001](001-core-library-and-extension-points.md), whose `ParrotCore` held every behaviour.

## 1. Decision

- **Two libraries.** `ParrotCore` is the engine and depends only on WhisperKit. `ParrotApp` holds the dictation loop, delivery at the cursor, `Settings` and `SettingsStore`, stats, the UI and the Sparkle updater, and depends on `ParrotCore`. The `parrot` executable depends on `ParrotApp`; `parrot-bench` depends on `ParrotCore` only.
- **A library product.** `Package.swift` exports `ParrotCore`. Linking it compiles neither `ParrotApp` nor Sparkle.
- **Three access levels.** `public` is the API another app uses: `HotkeyMonitor`, `Gesture`, `AudioCapture`, `Transcriber` and `TranscriptionContext`, `WhisperKitTranscriber`, `ModelRegistry`, `DictionaryStore`, `DictionaryContext`, `DictionaryProcessor`, `Transcript`, `TranscriptProcessor`, and the config, settings and dictionary paths. The rest of the engine is `package`, visible to this package's targets only. App code stays internal.
- **One model download, one dictionary.** An app linking the engine uses the same `Paths`, so it shares Parrot's downloaded models and `~/.config/parrot/dictionary`.
- **The engine reads only its own settings.** It decodes the `dictionary` key of `settings.json`, never the whole `Settings` value, which belongs to the app.

## 2. Rationale

An app that wants push-to-talk transcription would otherwise link all of `ParrotCore`, and with it Sparkle's framework, Parrot's windows and its settings store. Sparkle alone means embedding and signing another framework for no benefit.

Naming the new library `ParrotEngine` and leaving the app in `ParrotCore` was rejected: "core" already reads as the engine, the package exported no products before this, so no outside code depended on the old shape, and the engine files keep their history. Cursor delivery (`Delivery`, `FocusSnapshot`, `Spacing`, `TextInjector`) stays in the app because no other app needs it yet; moving it later is a small change.

## 3. Design Implications

- A type becomes `public` only when an app outside this package needs it. Parrot's own targets use `package`.
- A `public` struct that other apps construct declares a `public init`, since the implicit memberwise initializer is internal.
- The engine never imports Sparkle, SwiftUI or ServiceManagement, and never reads `Settings` or `SettingsStore`.
- Tests that cover app types import both modules.

## 4. When to Revisit

- If another app needs cursor delivery, move the four delivery files into the engine and make `Delivery` public.
- If the engine's public API needs versioning for outside apps, tag engine releases separately from Parrot.app releases.
