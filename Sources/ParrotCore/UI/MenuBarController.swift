import AppKit

/// Status bar item in the top-right of the menu bar. Shows recording state at
/// a glance and provides the only persistent control surface for the daemon
/// (since we run as `.accessory` — no dock icon, no main window).
///
/// The menu has named slots, top to bottom: `statusLine`, `modelLine`,
/// `grantPermissionsItem`, `settingsItem`, `checkForUpdatesItem`, `quitItem`. Features update a slot
/// rather than rebuilding the menu.
@MainActor
final class MenuBarController {
    private static func readyStatus(_ key: HotkeyKey) -> String { "idle · \(key.usageHint)" }

    private let statusItem: NSStatusItem
    /// Slot: what the dictation loop is doing. Driven as a `DictationObserver`.
    let statusLine: NSMenuItem
    /// Slot: the loaded model.
    let modelLine: NSMenuItem
    /// Slot: reopens the onboarding window (#51). Shown in Parrot.app while
    /// a permission is missing.
    let grantPermissionsItem: NSMenuItem
    /// What `grantPermissionsItem` does; set by `OnboardingWindow`.
    var onGrantPermissions: (() -> Void)?
    /// Slot: opens the Settings window (#41) through `onOpenSettings`.
    let settingsItem: NSMenuItem
    /// Called by Settings…; set by the daemon, which owns the window.
    var onOpenSettings: (() -> Void)?
    /// Slot: asks Sparkle to check now. Hidden unless the updater is running,
    /// which it is only in Parrot.app's release builds.
    let checkForUpdatesItem: NSMenuItem
    /// Slot: quits parrot.
    let quitItem: NSMenuItem
    /// Slots: the History window, the last dictations, and the file drop box.
    let historyItem: NSMenuItem
    private let recentMenu = NSMenu()
    let transcribeFileItem: NSMenuItem

    /// A degraded hotkey tap replaces the idle line, so the menu bar does not
    /// claim fn works when it does not (#37).
    private var hotkeyHealth: HotkeyHealth = .ok
    /// The key the idle line tells the user to hold (#42).
    private var hotkey: HotkeyKey = .fn
    private var isIdle = true
    private var idleStatus: String { hotkeyHealth.statusText ?? Self.readyStatus(hotkey) }

    init(modelID: String) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let menu = NSMenu()
        menu.autoenablesItems = false

        statusLine = NSMenuItem(title: Self.readyStatus(.fn), action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)

        modelLine = NSMenuItem(title: "model: \(modelID)", action: nil, keyEquivalent: "")
        modelLine.isEnabled = false
        menu.addItem(modelLine)

        grantPermissionsItem = NSMenuItem(
            title: "Grant Permissions…",
            action: #selector(grantPermissionsClicked),
            keyEquivalent: ""
        )
        grantPermissionsItem.isHidden = true
        menu.addItem(grantPermissionsItem)

        menu.addItem(.separator())

        historyItem = NSMenuItem(title: "History…", action: #selector(historyClicked), keyEquivalent: "")
        menu.addItem(historyItem)
        let recentItem = NSMenuItem(title: "Recent", action: nil, keyEquivalent: "")
        recentItem.submenu = recentMenu
        menu.addItem(recentItem)
        transcribeFileItem = NSMenuItem(title: "Transcribe file…", action: #selector(transcribeFileClicked), keyEquivalent: "")
        menu.addItem(transcribeFileItem)

        menu.addItem(.separator())

        settingsItem = NSMenuItem(title: "Settings…", action: #selector(settingsClicked), keyEquivalent: ",")
        menu.addItem(settingsItem)

        checkForUpdatesItem = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(checkForUpdatesClicked),
            keyEquivalent: ""
        )
        checkForUpdatesItem.isHidden = !Updater.isRunning
        menu.addItem(checkForUpdatesItem)

        quitItem = NSMenuItem(
            title: "Quit parrot",
            action: #selector(quitClicked),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        statusItem.menu = menu
        quitItem.target = self
        settingsItem.target = self
        checkForUpdatesItem.target = self
        grantPermissionsItem.target = self
        historyItem.target = self
        transcribeFileItem.target = self
        configureButton()
        rebuildRecent()
        NotificationCenter.default.addObserver(forName: Recordings.changed, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildRecent() }
        }
    }

    /// Shows the History and file-drop keys after their menu titles.
    func setShortcutKeys(history: FunctionKey, fileDrop: FunctionKey) {
        historyItem.title = "History…" + history.menuSuffix
        transcribeFileItem.title = "Transcribe file…" + fileDrop.menuSuffix
    }

    private func rebuildRecent() {
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

    func setStatus(_ text: String) {
        statusLine.title = text
    }

    func setHotkeyHealth(_ health: HotkeyHealth) {
        hotkeyHealth = health
        if isIdle { setStatus(idleStatus) }
    }

    func setHotkey(_ key: HotkeyKey) {
        hotkey = key
        if isIdle { setStatus(idleStatus) }
    }

    func setModel(_ modelID: String) {
        modelLine.title = "model: \(modelID)"
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        let image = Self.birdImage()
        image?.isTemplate = true
        button.image = image
    }

    // Inlined Lucide bird SVG. Keeping it in source means the executable has
    // no separate resource bundle to install alongside it — true single-binary.
    static let birdSVG = """
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

    @objc private func settingsClicked() {
        onOpenSettings?()
    }

    @objc private func grantPermissionsClicked() {
        onGrantPermissions?()
    }

    @objc private func checkForUpdatesClicked() {
        Updater.checkForUpdates()
    }

    @objc private func historyClicked() {
        HistoryWindow.show()
    }

    @objc private func transcribeFileClicked() {
        DropBox.show()
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
}

extension MenuBarController: DictationObserver {
    func dictationStarted() {
        isIdle = false
        setStatus("● recording")
    }

    func dictationTranscribing() {
        isIdle = false
        setStatus("transcribing…")
    }

    func dictationFinished(_ result: DictationResult) {
        isIdle = true
        setStatus(idleStatus)
    }

    func dictationFailed(_ error: Error) {
        isIdle = true
        setStatus(idleStatus)
    }
}
