import AppKit

@MainActor
enum TranscriptionResultPresenter {
    static func showRecordingFailed(_ error: Error, saved: URL?) {
        let alert = NSAlert()
        alert.messageText = "Transcription failed"
        alert.alertStyle = .warning
        guard let saved else {
            alert.informativeText = "\(error.localizedDescription)\n\nThe recording could not be saved."
            alert.runModal()
            return
        }
        alert.informativeText = "\(error.localizedDescription)\n\nThe recording is saved in History, where you can transcribe it again."
        alert.addButton(withTitle: "Open History")
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn {
            HistoryWindow.show()
        }
    }
}
