import AppKit
import SwiftUI

/// A window listing the last few dictations: copy any transcript, or
/// transcribe recordings that failed.
@MainActor
enum HistoryWindow {
    static let model = HistoryModel()
    private static var window: NSWindow?

    static func show(retrying wav: URL? = nil) {
        if window == nil {
            let host = NSHostingController(rootView: HistoryView(model: model))
            host.sizingOptions = []  // let setContentSize win over SwiftUI's minimum size
            let w = NSWindow(contentViewController: host)
            w.title = "Parrot History"
            w.setContentSize(NSSize(width: 540, height: 600))
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        model.reload()
        if let wav { model.retry(wav) }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// The History key: open History, or close it if it's already in front.
    static func toggle() {
        if let window, window.isKeyWindow {
            window.orderOut(nil)
        } else {
            show()
        }
    }
}

@MainActor
final class HistoryModel: ObservableObject {
    struct Item: Identifiable {
        let wav: URL
        let text: String?
        var id: URL { wav }
    }

    @Published private(set) var items: [Item] = []
    @Published private(set) var busy: Set<URL> = []
    @Published private(set) var errors: [URL: String] = [:]
    @Published private(set) var copied: URL?
    /// Set at startup to the on-device transcriber.
    var transcribe: (URL) async throws -> String = { _ in throw TranscriberError.notLoaded }

    init() {
        NotificationCenter.default.addObserver(forName: Recordings.changed, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    func reload() {
        Recordings.prune()
        items = Recordings.recent().map { Item(wav: $0.wav, text: $0.text) }
    }

    func retry(_ wav: URL) {
        guard !busy.contains(wav) else { return }
        busy.insert(wav)
        errors[wav] = nil
        Task {
            do {
                Recordings.saveTranscript(try await transcribe(wav), for: wav)
            } catch {
                errors[wav] = error.localizedDescription
            }
            busy.remove(wav)
        }
    }

    func copy(_ item: Item) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.text ?? "", forType: .string)
        copied = item.wav
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if copied == item.wav { copied = nil }
        }
    }
}

struct HistoryView: View {
    @ObservedObject var model: HistoryModel
    @State private var confirmingClear = false

    var body: some View {
        Group {
            if model.items.isEmpty {
                ContentUnavailableView(
                    "No recordings yet",
                    systemImage: "waveform",
                    description: Text("Your last \(Recordings.keep) dictations show up here.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(model.items) { RecordingCard(item: $0, model: model) }
                    }
                    .padding(14)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 320)
        .toolbar {
            Button(role: .destructive) {
                confirmingClear = true
            } label: {
                Label("Clear History", systemImage: "trash")
            }
            .disabled(model.items.isEmpty)
            Button {
                try? FileManager.default.createDirectory(at: Recordings.directory, withIntermediateDirectories: true)
                NSWorkspace.shared.open(Recordings.directory)
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }
        }
        .confirmationDialog("Delete all recordings and transcripts?", isPresented: $confirmingClear) {
            Button("Clear History", role: .destructive) { Recordings.clear() }
        }
    }
}

private struct RecordingCard: View {
    let item: HistoryModel.Item
    @ObservedObject var model: HistoryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let date = Recordings.date(of: item.wav) {
                    Text(date, format: .dateTime.hour().minute()).font(.headline)
                }
                Text(Duration.seconds(Recordings.duration(of: item.wav)), format: .time(pattern: .minuteSecond))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                ShareLink(item: item.wav) {
                    Label("Share audio", systemImage: "square.and.arrow.up")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Share the audio file")
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([item.wav])
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Show the audio file in Finder")
                action
            }
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor)))
    }

    @ViewBuilder private var action: some View {
        if item.text != nil {
            Button {
                model.copy(item)
            } label: {
                // Sized for the larger of each pair, so the swap doesn't resize the button.
                let copied = model.copied == item.wav
                Label {
                    ZStack(alignment: .leading) {
                        Text("Copied").hidden()
                        Text(copied ? "Copied" : "Copy")
                    }
                } icon: {
                    ZStack {
                        Image(systemName: "doc.on.doc").hidden()
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    }
                }
            }
            .disabled(item.text?.isEmpty ?? true)
        } else if model.busy.contains(item.wav) {
            ProgressView().controlSize(.small)
        } else {
            Button {
                model.retry(item.wav)
            } label: {
                Label("Transcribe", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder private var content: some View {
        if let text = item.text {
            Text(text.isEmpty ? "No speech detected" : text)
                .foregroundStyle(text.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if model.busy.contains(item.wav) {
            Text("Transcribing…").foregroundStyle(.secondary)
        } else {
            Label(model.errors[item.wav] ?? "Not transcribed", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }
}
