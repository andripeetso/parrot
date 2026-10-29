import AppKit
import CoreGraphics
import Foundation

/// Inserts text at the cursor by pasting it: the text goes on the clipboard,
/// ⌘V is synthesized, and the previous clipboard contents come back shortly
/// after. Typing it as synthetic unicode key events dropped text in Electron
/// apps; pasting lands in one piece everywhere a paste works.
enum TextInjector {
    private static let vKeycode: CGKeyCode = 9  // physical V key, any layout
    private static let restoreDelay: TimeInterval = 0.6

    static func inject(_ text: String) {
        guard !text.isEmpty else { return }
        if !CGPreflightPostEventAccess() {
            FileHandle.standardError.write(Data(
                "  can't post ⌘V (accessibility not granted); transcript left on the clipboard\n".utf8
            ))
        }

        let pasteboard = NSPasteboard.general
        let saved = snapshot(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let changeCount = pasteboard.changeCount

        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKeycode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKeycode, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
            // Leave the clipboard alone if something else changed it meanwhile.
            guard pasteboard.changeCount == changeCount, !saved.isEmpty else { return }
            pasteboard.clearContents()
            pasteboard.writeObjects(saved)
        }
    }

    private static func snapshot(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
    }
}
