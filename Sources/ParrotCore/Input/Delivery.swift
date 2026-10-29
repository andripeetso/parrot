import Foundation

/// A transcript that was not inserted at the cursor, with the line the
/// overlay shows.
enum DeliveryError: UserFacingError, Equatable {
    /// A password field had focus at start or at delivery. Nothing was typed
    /// or copied.
    case secureField

    var userMessage: String {
        switch self {
        case .secureField: return "password field, transcript discarded"
        }
    }
}

/// Where a finished transcript goes. Pure, so it is tested.
enum DeliveryDecision: Equatable {
    /// Insert at the cursor.
    case inject
    /// A secure field had focus at start or at delivery: drop the transcript.
    case discardSecure

    /// Goes wherever focus is at delivery, even if it moved during the
    /// dictation: clicking around while talking and back before stopping is
    /// normal. `start` is nil when no recording start was seen.
    static func decide(start: FocusSnapshot?, now: FocusSnapshot) -> DeliveryDecision {
        if start?.isSecure == true || now.isSecure { return .discardSecure }
        return .inject
    }
}

/// The delivery step of the dictation loop: checks for a password field at
/// recording start and now, then injects or discards. An
/// injected transcript gets a trailing space, and a leading one when the
/// text before the cursor needs it (`Spacing`).
@MainActor
final class TextDelivery {
    private let injector: TextInjector

    init(mode: InjectMode) {
        self.injector = TextInjector(mode: mode)
    }

    /// Throws `DeliveryError` when the transcript did not reach the cursor.
    func deliver(_ text: String, focusAtStart: FocusSnapshot?) throws {
        guard !text.isEmpty else { return }
        let now = FocusSnapshot.capture()
        switch DeliveryDecision.decide(start: focusAtStart, now: now) {
        case .inject:
            let before = now.element?.textBeforeCursor() ?? .unknown
            let spaced = Spacing.spaced(text, before: before)
            // The kind of character only: the log never carries text.
            Log.info("  before cursor: \(before.kind)\(spaced.first == " " && text.first != " " ? " · leading space" : "")")
            injector.inject(spaced)
        case .discardSecure:
            let when = focusAtStart?.isSecure == true ? "recording start" : "delivery"
            Log.info("  secure field focused at \(when); transcript discarded")
            throw DeliveryError.secureField
        }
    }
}
