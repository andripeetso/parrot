import AppKit

/// A short sound when recording starts and stops.
@MainActor
final class Sounds: DictationObserver {
    /// Set from `ExtrasSettings.sounds`.
    var enabled = true
    private let start = NSSound(named: "Tink")
    private let stop = NSSound(named: "Pop")

    func dictationStarted() { play(start) }
    func dictationTranscribing() { play(stop) }

    private func play(_ sound: NSSound?) {
        guard enabled, let sound else { return }
        sound.stop()
        sound.play()
    }
}

/// When a transcription fails, says the audio is safe and offers History.
@MainActor
final class FailureAlert: DictationObserver {
    func dictationFailed(_ error: Error) {
        guard let failure = error as? TranscriptionFailed else { return }
        // After this turn, so the overlay and menu bar settle first.
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Transcription failed"
            alert.alertStyle = .warning
            guard failure.saved != nil else {
                alert.informativeText = "\(failure.underlying.localizedDescription)\n\nThe recording could not be saved."
                alert.runModal()
                return
            }
            alert.informativeText = "\(failure.underlying.localizedDescription)\n\nThe recording is saved in History, where you can transcribe it again."
            alert.addButton(withTitle: "Open History")
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                HistoryWindow.show()
            }
        }
    }
}
