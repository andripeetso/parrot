import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The file-drop key: a drop zone for audio/video files. Each file is transcribed on-device in
/// the background, saved to History, and announced with a toast when done.
@MainActor
enum DropBox {
    static let model = DropBoxModel()
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: DropBoxView(model: model)))
            w.title = "Transcribe Files"
            w.styleMask.remove(.resizable)
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    static func toggle() {
        if let window, window.isKeyWindow {
            window.orderOut(nil)
        } else {
            show()
        }
    }
}

@MainActor
final class DropBoxModel: ObservableObject {
    struct Job: Identifiable {
        let id = UUID()
        let name: String
    }

    @Published private(set) var jobs: [Job] = []
    /// Set at startup to the on-device transcriber.
    var transcribe: ([Float]) async throws -> String = { _ in throw TranscriberError.notLoaded }

    func add(_ urls: [URL]) {
        for url in urls {
            guard UTType(filenameExtension: url.pathExtension)?.conforms(to: .audiovisualContent) == true else {
                Toast.show(title: "Not an audio or video file", subtitle: url.lastPathComponent)
                continue
            }
            let job = Job(name: url.lastPathComponent)
            jobs.append(job)
            Task {
                do {
                    // Decode + save off main (the key tap runs there). Saving puts it in
                    // History, so a failed transcription can be retried from there.
                    let (samples, wav) = try await Task.detached {
                        let samples = try AudioFileLoader.load(url: url)
                        guard !samples.isEmpty else { throw AudioFileLoader.LoaderError.invalidFormat }
                        return (samples, Recordings.save(samples))
                    }.value
                    let text = try await transcribe(samples)
                    if let wav { Recordings.saveTranscript(text, for: wav) }
                    Toast.show(title: "Transcription ready", subtitle: job.name, text: text)
                } catch {
                    Toast.show(title: "Couldn't transcribe", subtitle: "\(job.name): \(error.localizedDescription)")
                }
                jobs.removeAll { $0.id == job.id }
            }
        }
    }

    func choose() {
        let panel = NSOpenPanel()
        panel.prompt = "Transcribe"
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.audiovisualContent]
        guard panel.runModal() == .OK else { return }
        add(panel.urls)
    }
}

private struct DropBoxView: View {
    @ObservedObject var model: DropBoxModel
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 8) {
                Image(systemName: "waveform.badge.plus")
                    .font(.system(size: 34))
                    .foregroundStyle(targeted ? Color.accentColor : .secondary)
                Text("Drop audio or video here").font(.headline)
                Text("Transcribed on this Mac in the background").font(.caption).foregroundStyle(.secondary)
                Button("Choose File…") { model.choose() }
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, minHeight: 180)
            .background(RoundedRectangle(cornerRadius: 12).fill(targeted ? Color.accentColor.opacity(0.08) : .clear))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .foregroundStyle(targeted ? Color.accentColor : Color.secondary.opacity(0.5))
            )
            .dropDestination(for: URL.self) { urls, _ in
                model.add(urls)
                return true
            } isTargeted: { targeted = $0 }

            ForEach(model.jobs) { job in
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(job.name).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text("Transcribing…").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Small top-right toast. Parrot is a bare binary, not an .app bundle, so the
/// system notification APIs aren't available to it.
@MainActor
enum Toast {
    private static var panel: NSPanel?
    private static var hideTask: Task<Void, Never>?

    static func show(title: String, subtitle: String, text: String? = nil) {
        let panel = self.panel ?? {
            let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.level = .floating
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            self.panel = p
            return p
        }()
        let host = NSHostingController(rootView: ToastView(title: title, subtitle: subtitle, text: text))
        panel.contentViewController = host
        let size = host.view.fittingSize
        if let screen = NSScreen.main?.visibleFrame {
            panel.setFrame(NSRect(x: screen.maxX - size.width - 16, y: screen.maxY - size.height - 16,
                                  width: size.width, height: size.height), display: true)
        }
        panel.orderFrontRegardless()
        NSSound(named: "Glass")?.play()

        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(text == nil ? 5 : 12))
            if !Task.isCancelled { hide() }
        }
    }

    static func hide() {
        hideTask?.cancel()
        panel?.orderOut(nil)
    }
}

private struct ToastView: View {
    let title: String
    let subtitle: String
    let text: String?
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                Button { Toast.hide() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
            Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
            if let text {
                Text(text.isEmpty ? "No speech detected" : text).lineLimit(3)
                HStack {
                    Spacer()
                    Button("Open History") {
                        HistoryWindow.show()
                        Toast.hide()
                    }
                    Button(copied ? "Copied" : "Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        copied = true
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(minWidth: 70)
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .frame(width: 340)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
