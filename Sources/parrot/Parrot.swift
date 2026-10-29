import AppKit
import ArgumentParser
import Foundation
import WhisperKit

@main
struct Parrot: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "parrot",
        abstract: "Minimal macOS dictation daemon. Hold Fn (or tap F13), speak, release.",
        subcommands: [Run.self, Setup.self, Doctor.self, Models.self, Install.self],
        defaultSubcommand: Run.self
    )
}

struct Run: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run the daemon (default)."
    )

    @Flag(name: .long, help: "Skip permission checks at startup.")
    var skipDoctor: Bool = false

    @Flag(name: .long, help: "Print every keyboard event the tap sees (debug).")
    var debugHotkey: Bool = false

    @Flag(name: .long, help: "Write each capture to /tmp/parrot-last.wav for inspection.")
    var dumpWav: Bool = false

    @Flag(name: .long, help: "Disable the on-screen recording overlay.")
    var noOverlay: Bool = false

    @Flag(name: .long, help: "Disable the start/stop recording sounds.")
    var noSounds: Bool = false

    @Option(name: .long, help: "Model id to use. Defaults to the recommended model.")
    var model: String?

    @Option(
        name: .long,
        help: "Push-to-talk key. Options: \(HotkeyMonitor.Hotkey.allCases.map(\.rawValue).joined(separator: ", "))."
    )
    var hotkey: HotkeyMonitor.Hotkey?

    @Option(
        name: .long,
        help: "Speech-to-text server tried before the on-device model (POST WAV, returns {\"text\"}). Empty to disable."
    )
    var server: String = "http://192.168.8.237:7886/api/transcribe"

    func run() throws {
        let selectedHotkey = hotkey ?? HotkeyPreferences.selected
        if let hotkey {
            HotkeyPreferences.selected = hotkey
        }

        if !skipDoctor {
            let checks = DoctorReport.run(checkFnMapping: selectedHotkey == .fn)
            if !DoctorReport.allOK(checks) {
                FileHandle.standardError.write(Data("startup checks failed:\n".utf8))
                DoctorReport.print(checks)
                FileHandle.standardError.write(Data("\nfix the above or pass --skip-doctor\n".utf8))
                throw ExitCode(1)
            }
        }

        let chosenModel: TranscriptionModel
        if let id = model {
            guard let m = ModelRegistry.find(id) else {
                FileHandle.standardError.write(Data("unknown model: \(id)\n".utf8))
                FileHandle.standardError.write(Data("run `parrot models list` to see options.\n".utf8))
                throw ExitCode(1)
            }
            chosenModel = m
        } else {
            guard let m = ModelRegistry.recommended() else {
                FileHandle.standardError.write(Data("no models registered\n".utf8))
                throw ExitCode(1)
            }
            chosenModel = m
        }

        let localTranscriber = WhisperKitTranscriber(model: chosenModel)
        let remoteTranscriber = URL(string: server).flatMap { $0.host == nil ? nil : RemoteTranscriber(endpoint: $0) }
        let transcriber = FallbackTranscriber(remote: remoteTranscriber, local: localTranscriber)
        if let remoteTranscriber {
            Task.detached { await remoteTranscriber.warmUp() }
        }
        // Load in the background so hotkeys work right away: when macOS has evicted its
        // compiled copy of the model, recompiling takes minutes. Until it's ready,
        // dictation uses the server, or waits for the load if the server is down.
        Task.detached {
            do {
                try await localTranscriber.warmUp()
            } catch {
                FileHandle.standardError.write(Data("warmup failed: \(error)\n".utf8))
            }
        }

        Recordings.prune()
        Sounds.enabled = !noSounds
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let monitor = HotkeyMonitor(hotkey: selectedHotkey, debug: debugHotkey)
        monitor.onHistoryKey = { MainActor.assumeIsolated { HistoryWindow.toggle() } }
        monitor.onDropBoxKey = { MainActor.assumeIsolated { DropBox.toggle() } }
        let capture = AudioCapture()
        let dumpWav = self.dumpWav
        let overlay: RecordingOverlay? = noOverlay ? nil : MainActor.assumeIsolated { RecordingOverlay() }
        if let overlay {
            capture.onLevel = { level in overlay.pushLevel(level) }
        }
        MainActor.assumeIsolated {
            HistoryWindow.model.transcribe = { url in
                let samples = try await Task.detached { try AudioFileLoader.load(url: url) }.value  // off main: the key tap runs there
                guard !samples.isEmpty else { throw AudioFileLoader.LoaderError.invalidFormat }
                return try await localTranscriber.transcribe(samples)
            }
            DropBox.model.transcribe = { try await localTranscriber.transcribe($0) }
        }
        var menuBar: MenuBarController!
        menuBar = MainActor.assumeIsolated {
            MenuBarController(
                modelID: transcriber.modelID,
                hotkey: selectedHotkey
            )
        }

        MainActor.assumeIsolated {
            SettingsWindow.onDictationKeyChanged = { key in
                monitor.setHotkey(key)
                menuBar.setHotkey(key)
            }
        }

        do {
            try monitor.start { event in
                switch event {
                case .pressed:
                    do {
                        Sounds.playStart()
                        try capture.start()
                        FileHandle.standardError.write(Data("● recording\n".utf8))
                        MainActor.assumeIsolated {
                            overlay?.show(.recording)
                            menuBar.setRecording(true)
                        }
                    } catch {
                        FileHandle.standardError.write(Data("capture failed: \(error)\n".utf8))
                    }
                case .released:
                    let samples = capture.stop()
                    Sounds.playStop()
                    MainActor.assumeIsolated {
                        overlay?.show(.transcribing)
                        menuBar.setTranscribing()
                    }
                    let seconds = Double(samples.count) / AudioCapture.targetSampleRate
                    let rms = computeRMS(samples)
                    FileHandle.standardError.write(Data(
                        String(format: "○ captured %.2fs · rms %.3f\n", seconds, rms).utf8
                    ))
                    if dumpWav, !samples.isEmpty {
                        let path = "/tmp/parrot-last.wav"
                        do {
                            try WAVWriter.write(samples: samples, sampleRate: 16_000, to: path)
                            FileHandle.standardError.write(Data("  wrote \(path)\n".utf8))
                        } catch {
                            FileHandle.standardError.write(Data("  wav write failed: \(error)\n".utf8))
                        }
                    }
                    guard !samples.isEmpty else {
                        MainActor.assumeIsolated {
                            overlay?.hide()
                            menuBar.setRecording(false)
                        }
                        return
                    }
                    Task {
                        let saved = Recordings.save(samples)
                        let started = Date()
                        do {
                            let text: String
                            do {
                                text = try await transcriber.transcribe(samples)
                            } catch {
                                // One more on-device attempt before giving up; the audio is in History either way.
                                FileHandle.standardError.write(Data("transcription failed: \(error), retrying on-device\n".utf8))
                                text = try await localTranscriber.transcribe(samples)
                            }
                            if let saved { Recordings.saveTranscript(text, for: saved) }
                            let elapsed = Date().timeIntervalSince(started)
                            FileHandle.standardError.write(Data(
                                String(format: "→ %.2fs · %@\n", elapsed, text).utf8
                            ))
                            await MainActor.run {
                                TextInjector.inject(text)
                                overlay?.hide()
                                menuBar.setRecording(false)
                            }
                        } catch {
                            FileHandle.standardError.write(Data("transcription failed: \(error)\n".utf8))
                            await MainActor.run {
                                overlay?.hide()
                                menuBar.setRecording(false)
                                TranscriptionResultPresenter.showRecordingFailed(error, saved: saved)
                            }
                        }
                    }
                }
            }
        } catch {
            FileHandle.standardError.write(Data("failed to register hotkey tap: \(error)\n".utf8))
            FileHandle.standardError.write(Data("run `parrot setup` to configure permissions.\n".utf8))
            throw ExitCode(1)
        }

        let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        sigint.setEventHandler {
            FileHandle.standardError.write(Data("\nshutting down\n".utf8))
            monitor.stop()
            NSApp.terminate(nil)
        }
        sigint.resume()
        signal(SIGINT, SIG_IGN)

        FileHandle.standardError.write(Data(
            "listening · \(selectedHotkey.usageHint) · model: \(transcriber.modelID) · ^C to quit\n".utf8
        ))
        app.run()
    }
}

extension HotkeyMonitor.Hotkey: ExpressibleByArgument {}

struct Doctor: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check microphone, accessibility, and Fn key configuration."
    )

    func run() throws {
        let checks = DoctorReport.run()
        DoctorReport.print(checks)
        if !DoctorReport.allOK(checks) {
            throw ExitCode(1)
        }
    }
}

struct Models: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage transcription models.",
        subcommands: [List.self, Download.self]
    )

    struct List: ParsableCommand {
        func run() throws {
            for m in ModelRegistry.shared {
                let star = m.recommended ? "★" : " "
                let id = m.id.padding(toLength: 26, withPad: " ", startingAt: 0)
                let langs = "[\(m.languages.joined(separator: ","))]"
                    .padding(toLength: 9, withPad: " ", startingAt: 0)
                let size = String(format: "%5d MB", m.sizeMB)
                print("\(star) \(id) \(size)  \(langs)  \(m.displayName)")
            }
        }
    }

    struct Download: ParsableCommand {
        @Argument(help: "Model id to download.") var id: String

        func run() throws {
            guard let m = ModelRegistry.find(id) else {
                print("unknown model: \(id)")
                throw ExitCode(1)
            }
            let t = WhisperKitTranscriber(model: m)

            let sem = DispatchSemaphore(value: 0)
            var capturedError: Error?
            Task.detached {
                do { try await t.warmUp() } catch { capturedError = error }
                sem.signal()
            }
            sem.wait()
            if let e = capturedError { throw e }
        }
    }
}
