import ApplicationServices
import CoreGraphics

/// System-wide shortcuts on plain function keys (F13 dictation, F14 History,
/// F15 file drop). An event tap rather than `RegisterEventHotKey`: macOS's
/// own shortcuts (F14/F15 are display brightness) win over Carbon hotkeys,
/// but a session tap sees the key first. Bound keys are swallowed, so macOS
/// doesn't also run its own action; every other key passes straight through
/// untouched, after one integer compare.
@MainActor
final class FunctionKeys {
    static let shared = FunctionKeys()

    private var actions: [Int64: () -> Void] = [:]
    private var tap: CFMachPort?
    private var retry: Timer?
    private var watchdog: Timer?

    /// Bound keycodes, read from the tap callback on the main thread.
    fileprivate var keycodes: Set<Int64> = []

    /// Replaces every binding.
    func bind(_ bindings: [(keycode: UInt32, action: () -> Void)]) {
        actions = Dictionary(bindings.map { (Int64($0.keycode), $0.action) }, uniquingKeysWith: { $1 })
        keycodes = Set(actions.keys)
        Log.info("function keys: \(keycodes.sorted())")
        installTap()
    }

    fileprivate func fire(_ keycode: Int64) {
        actions[keycode]?()
    }

    fileprivate func reenable() {
        if let tap, !CGEvent.tapIsEnabled(tap: tap) {
            Log.info("function key tap disabled; re-enabled")
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    /// Needs Accessibility; until it's granted, tries again every 2 s.
    private func installTap() {
        guard tap == nil, retry == nil else { return }
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        guard AXIsProcessTrusted(), let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,  // not listenOnly, so bound keys can be swallowed
            eventsOfInterest: mask,
            callback: functionKeyCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            retry = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.retry = nil
                    self?.installTap()
                }
            }
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        Log.info("function key tap on")
        // macOS can switch a tap off without an event saying so.
        watchdog = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reenable() }
        }
    }
}

private func functionKeyCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let keys = Unmanaged<FunctionKeys>.fromOpaque(userInfo).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        DispatchQueue.main.async { MainActor.assumeIsolated { keys.reenable() } }
        return Unmanaged.passUnretained(event)
    }
    // The tap's run loop source is on the main run loop.
    let keycode = event.getIntegerValueField(.keyboardEventKeycode)
    let bound = MainActor.assumeIsolated { keys.keycodes.contains(keycode) }
    guard bound else { return Unmanaged.passUnretained(event) }
    if type == .keyDown, event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
        DispatchQueue.main.async { MainActor.assumeIsolated { keys.fire(keycode) } }
    }
    return nil
}
