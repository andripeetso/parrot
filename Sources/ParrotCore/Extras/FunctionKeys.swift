import Carbon.HIToolbox

/// System-wide shortcuts on plain function keys (F13 dictation, F14 History,
/// F15 file drop) through Carbon's `RegisterEventHotKey`. Unlike the modifier
/// tap it needs no Accessibility grant, sees only these keys, and swallows
/// them, so macOS doesn't also run its own action for them.
@MainActor
final class FunctionKeys {
    static let shared = FunctionKeys()

    private var refs: [EventHotKeyRef] = []
    private var actions: [UInt32: () -> Void] = [:]
    private var handler: EventHandlerRef?

    /// Replaces every binding. A key another app already holds is logged and skipped.
    func bind(_ bindings: [(keycode: UInt32, action: () -> Void)]) {
        installHandler()
        refs.forEach { UnregisterEventHotKey($0) }
        refs = []
        actions = [:]
        for (index, binding) in bindings.enumerated() {
            let id = UInt32(index + 1)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                binding.keycode, 0, EventHotKeyID(signature: OSType(0x5052_5254), id: id),  // 'PRRT'
                GetApplicationEventTarget(), 0, &ref
            )
            guard status == noErr, let ref else {
                Log.warning("couldn't register key \(binding.keycode) (\(status))")
                continue
            }
            refs.append(ref)
            actions[id] = binding.action
        }
    }

    fileprivate func fire(_ id: UInt32) {
        actions[id]?()
    }

    private func installHandler() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(), functionKeyCallback, 1, &spec,
            Unmanaged.passUnretained(self).toOpaque(), &handler
        )
    }
}

private func functionKeyCallback(
    _: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var id = EventHotKeyID()
    let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
        nil, MemoryLayout<EventHotKeyID>.size, nil, &id
    )
    guard status == noErr else { return status }
    let keys = Unmanaged<FunctionKeys>.fromOpaque(userData).takeUnretainedValue()
    // Carbon delivers application-target events on the main thread.
    MainActor.assumeIsolated { keys.fire(id.id) }
    return noErr
}
