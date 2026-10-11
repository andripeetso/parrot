/// Where a transcript goes once the processors have run: the last step of
/// the dictation loop. `CursorDelivery` pastes it at the cursor; an app that
/// links ParrotCore can supply its own.
///
/// Throwing reports `dictationFailed` to the observers, and an error that
/// conforms to `UserFacingError` carries the line to show. Returning reports
/// `dictationFinished`. Async, so a delivery can be a network or socket send.
@MainActor
package protocol TranscriptDelivery: AnyObject {
    /// `focusAtStart` is what had focus when the recording started, or nil
    /// when no start was seen.
    func deliver(_ text: String, focusAtStart: FocusSnapshot?) async throws
}
