import AppKit
import UniformTypeIdentifiers

/// Status bar item in the top-right of the menu bar. Shows recording state at
/// a glance and provides the only persistent control surface for the daemon
/// (since we run as `.accessory` — no dock icon, no main window).
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let modelLabel: NSMenuItem
    private let stateLabel: NSMenuItem
    private let modelID: String
    private var hotkey: HotkeyMonitor.Hotkey
    private let recentMenu = NSMenu()
    private let historyItem = NSMenuItem(title: "History…", action: nil, keyEquivalent: "")
    private let transcribeFileItem = NSMenuItem(title: "Transcribe file…", action: nil, keyEquivalent: "")

    init(
        modelID: String,
        hotkey: HotkeyMonitor.Hotkey,
    ) {
        self.modelID = modelID
        self.hotkey = hotkey
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        stateLabel = NSMenuItem(
            title: "idle · \(hotkey.usageHint)",
            action: nil,
            keyEquivalent: ""
        )
        modelLabel = NSMenuItem(title: "model: \(modelID)", action: nil, keyEquivalent: "")
        super.init()

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        stateLabel.isEnabled = false
        menu.addItem(stateLabel)

        modelLabel.isEnabled = false
        menu.addItem(modelLabel)

        menu.addItem(.separator())

        historyItem.action = #selector(historyClicked)
        historyItem.target = self
        menu.addItem(historyItem)

        let recentItem = NSMenuItem(title: "Recent", action: nil, keyEquivalent: "")
        recentItem.submenu = recentMenu
        menu.addItem(recentItem)

        menu.addItem(.separator())

        transcribeFileItem.action = #selector(transcribeFileClicked)
        transcribeFileItem.target = self
        menu.addItem(transcribeFileItem)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(settingsClicked), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit parrot",
            action: #selector(quitClicked),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        configureButton(recording: false)
    }

    func setRecording(_ recording: Bool) {
        stateLabel.title = recording
            ? "● recording"
            : "idle · \(hotkey.usageHint)"
    }

    func setTranscribing() {
        stateLabel.title = "transcribing…"
    }


    private func configureButton(recording: Bool) {
        guard let button = statusItem.button else { return }
        let image = Self.birdImage()
        image?.isTemplate = true
        button.image = image
    }

    // Inlined Lucide bird SVG. Keeping it in source means the executable has
    // no separate resource bundle to install alongside it — true single-binary.
    private static let birdSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" \
    viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" \
    stroke-linecap="round" stroke-linejoin="round">\
    <path d="M16 7h.01"/>\
    <path d="M3.4 18H12a8 8 0 0 0 8-8V7a4 4 0 0 0-7.28-2.3L2 20"/>\
    <path d="m20 7 2 .5-2 .5"/>\
    <path d="M10 18v3"/>\
    <path d="M14 17.75V21"/>\
    <path d="M7 18a6 6 0 0 0 3.84-10.61"/>\
    </svg>
    """

    private static func birdImage() -> NSImage? {
        guard let data = birdSVG.data(using: .utf8),
              let image = NSImage(data: data)
        else { return nil }
        // Menu-bar status icons are nominally 18pt tall; size the SVG to match.
        image.size = NSSize(width: 16, height: 16)
        return image
    }

    /// Rebuilt from disk every time the menu opens, so it's always current.
    func menuWillOpen(_ menu: NSMenu) {
        historyItem.title = "History…" + Prefs.keySuffix(Prefs.historyKeycode)
        transcribeFileItem.title = "Transcribe file…" + Prefs.keySuffix(Prefs.dropBoxKeycode)
        Recordings.prune()
        recentMenu.removeAllItems()
        let recordings = Recordings.recent()
        if recordings.isEmpty {
            let empty = NSMenuItem(title: "No recordings yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            recentMenu.addItem(empty)
        }
        for (wav, text) in recordings {
            // Filenames are yyyy-MM-dd_HH-mm-ss; show HH:mm.
            let time = wav.deletingPathExtension().lastPathComponent.suffix(8).prefix(5).replacingOccurrences(of: "-", with: ":")
            let item: NSMenuItem
            if let text {
                let preview = text.isEmpty ? "(no speech)" : (text.count > 60 ? text.prefix(60) + "…" : text)
                item = NSMenuItem(title: "\(time) · \(preview)", action: #selector(copyRecent(_:)), keyEquivalent: "")
                item.representedObject = text
                item.toolTip = text
            } else {
                item = NSMenuItem(title: "\(time) · ⚠ no transcript, click to transcribe", action: #selector(retryRecent(_:)), keyEquivalent: "")
                item.representedObject = wav
            }
            item.target = self
            recentMenu.addItem(item)
        }
        recentMenu.addItem(.separator())
        let open = NSMenuItem(title: "Open History…", action: #selector(historyClicked), keyEquivalent: "")
        open.target = self
        recentMenu.addItem(open)
    }

    @objc private func historyClicked() {
        HistoryWindow.show()
    }

    @objc private func copyRecent(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func retryRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        HistoryWindow.show(retrying: url)
    }

    @objc private func quitClicked() {
        NSApp.terminate(nil)
    }

    func setHotkey(_ selected: HotkeyMonitor.Hotkey) {
        hotkey = selected
        setRecording(false)
    }

    @objc private func settingsClicked() {
        SettingsWindow.show()
    }

    @objc private func transcribeFileClicked() {
        DropBox.show()
    }
}
