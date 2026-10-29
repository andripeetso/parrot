import AppKit
import SwiftUI

/// History, shortcut keys, sounds and the LAN server: `ExtrasSettings`.
struct ExtrasSection: View {
    @ObservedObject var store: SettingsStore
    @State private var server = ""

    private var extras: ExtrasSettings { store.current.extras }

    var body: some View {
        SettingsGroup("History & Extras") {
            PillRow("Keep last \(extras.keepRecordings) recordings") {
                Stepper("", value: Binding(
                    get: { extras.keepRecordings },
                    set: { n in store.update { $0.extras.keepRecordings = n } }
                ), in: 5...100, step: 5)
                .labelsHidden()
            }
            PillRow("Recordings") {
                Button("Show in Finder") {
                    _ = try? Paths.prepareDirectory(Recordings.directory)
                    NSWorkspace.shared.open(Recordings.directory)
                }
                .buttonStyle(.pill)
            }
            keyRow("History key", \.historyKey)
            keyRow("File drop key", \.fileDropKey)
            PillRow("Sounds") {
                Toggle("Sounds", isOn: Binding(
                    get: { extras.sounds },
                    set: { on in store.update { $0.extras.sounds = on } }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Transcription server")
                TextField("http://host:7886/api/transcribe (empty = on-device only)", text: $server)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { store.update { $0.extras.server = server.isEmpty ? nil : server } }
                Text("Tried first; falls back to the Mac's model when it can't be reached. Press Return to save.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { server = extras.server ?? "" }
    }

    private func keyRow(_ label: String, _ field: WritableKeyPath<ExtrasSettings, FunctionKey>) -> some View {
        PillRow(label) {
            PillMenu(title: extras[keyPath: field].displayName) {
                ForEach(FunctionKey.allCases, id: \.self) { key in
                    Toggle(key.displayName, isOn: Binding(
                        get: { extras[keyPath: field] == key },
                        set: { on in if on { store.update { $0.extras[keyPath: field] = key } } }
                    ))
                }
            }
        }
    }
}
