import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Watches a single modifier key (default: Fn) and emits press/release edges.
/// Toggle keys (F13) emit `.pressed` on the first tap and `.released` on the next.
/// Requires Accessibility permission. If the tap fails to register, callers
/// will see an error from `start()`.
final class HotkeyMonitor {
    enum Event { case pressed, released }
    enum HotkeyError: Error { case tapCreateFailed }

    enum Hotkey: String, CaseIterable {
        case fn
        case leftOption = "left-option"
        case rightOption = "right-option"
        case leftCommand = "left-command"
        case rightCommand = "right-command"
        case leftControl = "left-control"
        case rightControl = "right-control"
        case leftShift = "left-shift"
        case rightShift = "right-shift"
        case f13

        var displayName: String {
            switch self {
            case .fn: return "Fn"
            case .leftOption: return "Left Option (⌥)"
            case .rightOption: return "Right Option (⌥)"
            case .leftCommand: return "Left Command (⌘)"
            case .rightCommand: return "Right Command (⌘)"
            case .leftControl: return "Left Control (⌃)"
            case .rightControl: return "Right Control (⌃)"
            case .leftShift: return "Left Shift (⇧)"
            case .rightShift: return "Right Shift (⇧)"
            case .f13: return "F13"
            }
        }

        /// Tap once to start recording, tap again to stop (instead of holding).
        var isToggle: Bool { self == .f13 }

        /// How to dictate with this key, for status text.
        var usageHint: String {
            isToggle ? "tap \(displayName) to start/stop" : "hold \(displayName) to dictate"
        }

        fileprivate var mask: CGEventFlags {
            switch self {
            case .fn: return .maskSecondaryFn
            case .leftOption, .rightOption: return .maskAlternate
            case .leftCommand, .rightCommand: return .maskCommand
            case .leftControl, .rightControl: return .maskControl
            case .leftShift, .rightShift: return .maskShift
            case .f13: return []
            }
        }

        fileprivate var keycode: Int64? {
            switch self {
            case .fn: return nil
            case .leftOption: return 58
            case .rightOption: return 61
            case .leftCommand: return 55
            case .rightCommand: return 54
            case .leftControl: return 59
            case .rightControl: return 62
            case .leftShift: return 56
            case .rightShift: return 60
            case .f13: return 105
            }
        }
    }

    private(set) var hotkey: Hotkey
    /// Called on the main thread when the History key (Settings, default F14) is
    /// pressed. That key is swallowed so macOS doesn't also run its own action.
    var onHistoryKey: (() -> Void)?
    /// Same, for the file drop key (default F15).
    var onDropBoxKey: (() -> Void)?
    private let debug: Bool
    private var onEvent: ((Event) -> Void)?
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isPressed = false
    private var permissionTimer: Timer?
    private var watchdog: Timer?

    init(hotkey: Hotkey = .fn, debug: Bool = false) {
        self.hotkey = hotkey
        self.debug = debug
    }

    func setHotkey(_ hotkey: Hotkey) {
        self.hotkey = hotkey
        isPressed = false
    }

    /// Starts listening. Without Accessibility permission this asks once and
    /// keeps waiting for the grant instead of failing: exiting made launchd
    /// relaunch parrot, which re-opened the system prompt in a loop.
    func start(onEvent: @escaping (Event) -> Void) throws {
        self.onEvent = onEvent

        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        if AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary) {
            try installTap()
            return
        }
        FileHandle.standardError.write(Data(
            "accessibility not granted — waiting. Enable parrot in System Settings → Privacy & Security → Accessibility.\n".utf8
        ))
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self, AXIsProcessTrusted() else { return }
            timer.invalidate()
            self.permissionTimer = nil
            do {
                try self.installTap()
                FileHandle.standardError.write(Data("✓ accessibility granted, hotkey active\n".utf8))
            } catch {
                FileHandle.standardError.write(Data("failed to register hotkey tap: \(error)\n".utf8))
            }
        }
    }

    private func installTap() throws {

        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        // .cgSessionEventTap is the right level for an accessibility-granted
        // user process (.cghidEventTap requires root).
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,  // not listenOnly, so F14 can be swallowed
                eventsOfInterest: mask,
                callback: hotkeyCallback,
                userInfo: userInfo
            )
        else {
            throw HotkeyError.tapCreateFailed
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.runLoopSource = source

        // macOS can switch the tap off without telling us (sleep, secure input,
        // a slow callback). Check every few seconds and turn it back on.
        watchdog = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let tap = self?.tap, !CGEvent.tapIsEnabled(tap: tap) else { return }
            FileHandle.standardError.write(Data("  hotkey tap was disabled, re-enabling\n".utf8))
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    /// Re-arms the tap after macOS disables it (timeout or permission change).
    fileprivate func reenable() {
        FileHandle.standardError.write(Data("  hotkey tap disabled by macOS, re-enabling\n".utf8))
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    func stop() {
        permissionTimer?.invalidate()
        permissionTimer = nil
        watchdog?.invalidate()
        watchdog = nil
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        onEvent = nil
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) {
        if debug {
            let flags = event.flags
            let keycode = event.getIntegerValueField(.keyboardEventKeycode)
            FileHandle.standardError.write(
                Data(
                    "  [debug] type=\(type.rawValue) keycode=\(keycode) flags=\(String(flags.rawValue, radix: 16))\n"
                        .utf8
                ))
        }
        if hotkey.isToggle {
            guard type == .keyDown,
                event.getIntegerValueField(.keyboardEventKeycode) == hotkey.keycode,
                event.getIntegerValueField(.keyboardEventAutorepeat) == 0
            else { return }
            isPressed.toggle()
            onEvent?(isPressed ? .pressed : .released)
            return
        }
        guard type == .flagsChanged else { return }
        if let expectedKeycode = hotkey.keycode {
            let keycode = event.getIntegerValueField(.keyboardEventKeycode)
            guard keycode == expectedKeycode else { return }
        }
        let pressed = event.flags.contains(hotkey.mask)
        guard pressed != isPressed else { return }
        isPressed = pressed
        onEvent?(pressed ? .pressed : .released)
    }
}

private func hotkeyCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        DispatchQueue.main.async { monitor.reenable() }
        return Unmanaged.passUnretained(event)
    }

    // 0 means "off" in Prefs (and is also the A key), so never match it.
    let keycode = Int(event.getIntegerValueField(.keyboardEventKeycode))
    if type == .keyDown || type == .keyUp, keycode != 0,
        keycode == Prefs.historyKeycode || keycode == Prefs.dropBoxKeycode
    {
        if type == .keyDown, event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
            let handler = keycode == Prefs.historyKeycode ? monitor.onHistoryKey : monitor.onDropBoxKey
            DispatchQueue.main.async { handler?() }
        }
        return nil
    }

    let copy = event.copy()
    DispatchQueue.main.async {
        if let copy {
            monitor.handle(type: type, event: copy)
        }
    }
    return Unmanaged.passUnretained(event)
}
