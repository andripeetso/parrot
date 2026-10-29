import Foundation

/// Every dictation is written here before transcription (plus a .txt transcript
/// once it succeeds), so the menu bar can list recent ones and failures can be retried.
enum Recordings {
    static let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("parrot/recordings", isDirectory: true)

    static var keep: Int { UserDefaults.standard.object(forKey: Prefs.keepRecordings) as? Int ?? 10 }

    /// Posted (on any thread) whenever a recording or transcript is added or removed.
    static let changed = Notification.Name("parrot.recordingsChanged")

    private static let nameFormat = "yyyy-MM-dd_HH-mm-ss"

    /// Returns the saved file, or nil if writing failed (transcription still proceeds).
    static func save(_ samples: [Float]) -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = nameFormat
        let url = directory.appendingPathComponent("\(formatter.string(from: Date())).wav")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try WAVWriter.data(samples: samples, sampleRate: Int(AudioCapture.targetSampleRate)).write(to: url)
            FileHandle.standardError.write(Data("  saved \(url.path)\n".utf8))
            prune()
            NotificationCenter.default.post(name: changed, object: nil)
            return url
        } catch {
            FileHandle.standardError.write(Data("  recording save failed: \(error)\n".utf8))
            return nil
        }
    }

    static func transcriptURL(for wav: URL) -> URL {
        wav.deletingPathExtension().appendingPathExtension("txt")
    }

    static func saveTranscript(_ text: String, for wav: URL) {
        try? text.write(to: transcriptURL(for: wav), atomically: true, encoding: .utf8)
        NotificationCenter.default.post(name: changed, object: nil)
    }

    static func date(of wav: URL) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = nameFormat
        return formatter.date(from: wav.deletingPathExtension().lastPathComponent)
    }

    /// Length in seconds, from the size of the 16 kHz 16-bit mono WAV we write.
    static func duration(of wav: URL) -> TimeInterval {
        let bytes = (try? wav.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 44
        return Double(max(bytes - 44, 0)) / (AudioCapture.targetSampleRate * 2)
    }

    static func isRecording(_ url: URL) -> Bool {
        url.deletingLastPathComponent().standardizedFileURL.path == directory.standardizedFileURL.path
    }

    /// Newest first. `text` is nil when no transcript exists (failed or still running).
    static func recent() -> [(wav: URL, text: String?)] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "wav" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .map { ($0, try? String(contentsOf: transcriptURL(for: $0), encoding: .utf8)) }
    }

    /// Keeps only the newest `keep` recordings (and their transcripts).
    static func prune() {
        let old = recent().dropFirst(keep)
        for (wav, _) in old {
            try? FileManager.default.removeItem(at: wav)
            try? FileManager.default.removeItem(at: transcriptURL(for: wav))
        }
        if !old.isEmpty { NotificationCenter.default.post(name: changed, object: nil) }
    }

    static func clear() {
        try? FileManager.default.removeItem(at: directory)
        NotificationCenter.default.post(name: changed, object: nil)
    }
}
