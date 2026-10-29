import AppKit
import SwiftUI

/// UserDefaults keys for settings that aren't hotkey-specific.
enum Prefs {
    static let historyKey = "historyKey"        // keycode, 0 = off
    static let dropBoxKey = "dropBoxKey"        // keycode, 0 = off
    static let keepRecordings = "keepRecordings"
    static let sounds = "sounds"

    static let functionKeys: [(name: String, code: Int)] = [("F14", 107), ("F15", 113), ("F16", 106), ("Off", 0)]

    static var historyKeycode: Int { UserDefaults.standard.object(forKey: historyKey) as? Int ?? 107 }
    static var dropBoxKeycode: Int { UserDefaults.standard.object(forKey: dropBoxKey) as? Int ?? 113 }

    /// " (F14)" for menu titles, or "" when the key is off.
    static func keySuffix(_ code: Int) -> String {
        functionKeys.first { $0.code == code && code != 0 }.map { "  (\($0.name))" } ?? ""
    }
}

@MainActor
enum SettingsWindow {
    /// Set at startup so a new dictation key takes effect immediately.
    static var onDictationKeyChanged: (HotkeyMonitor.Hotkey) -> Void = { _ in }
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            w.title = "Parrot Settings"
            w.styleMask.remove(.resizable)
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct SettingsView: View {
    @State private var dictationKey = HotkeyPreferences.selected
    @AppStorage(Prefs.historyKey) private var historyKey = 107
    @AppStorage(Prefs.dropBoxKey) private var dropBoxKey = 113
    @AppStorage(Prefs.keepRecordings) private var keep = 10
    @AppStorage(Prefs.sounds) private var sounds = true

    var body: some View {
        Form {
            Section("Keys") {
                Picker("Dictation key", selection: $dictationKey) {
                    ForEach(HotkeyMonitor.Hotkey.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .onChange(of: dictationKey) { _, key in
                    HotkeyPreferences.selected = key
                    SettingsWindow.onDictationKeyChanged(key)
                }
                Picker("History window key", selection: $historyKey) {
                    ForEach(Prefs.functionKeys, id: \.code) { Text($0.name).tag($0.code) }
                }
                Picker("File drop key", selection: $dropBoxKey) {
                    ForEach(Prefs.functionKeys, id: \.code) { Text($0.name).tag($0.code) }
                }
            }
            Section("History") {
                Stepper("Keep last \(keep) recordings", value: $keep, in: 5...100, step: 5)
                    .onChange(of: keep) { Recordings.prune() }
                Button("Show recordings in Finder") {
                    try? FileManager.default.createDirectory(at: Recordings.directory, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(Recordings.directory)
                }
            }
            Section("Sound") {
                Toggle("Play sounds when recording starts and stops", isOn: $sounds)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}
