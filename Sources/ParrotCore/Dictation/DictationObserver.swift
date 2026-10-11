import Foundation

/// Counts and timings for one delivered dictation. Never the text.
package struct DictationResult: Equatable, Sendable {
    /// Seconds of audio captured.
    package var captureDuration: TimeInterval
    /// Seconds the transcriber took.
    package var transcriptionTime: TimeInterval
    /// Characters delivered, after every `TranscriptProcessor`.
    package var charCount: Int
    /// Seconds to stop the capture engine and collect its samples.
    package var captureStop: TimeInterval = 0
    /// The transcriber's own breakdown, when the engine reports one.
    package var transcriber: TranscriberTimings?
    /// Seconds in the `TranscriptProcessor`s.
    package var processing: TimeInterval = 0
    /// Seconds in the `TranscriptDelivery`.
    package var delivery: TimeInterval = 0
    /// Seconds from the hotkey release to the text being delivered.
    package var releaseToText: TimeInterval = 0
    /// Seconds from the hotkey press to the capture time of the first
    /// recorded sample (#52): speech in that gap is lost. Nil if unknown.
    package var pressToFirstSample: TimeInterval?
}

package enum DictationError: Error {
    /// The hotkey was released with no audio captured.
    case noAudio
    /// The recording was discarded: a short tap, a chord, or a hotkey switch (#42).
    case cancelled
}

/// Follows the dictation loop: in Parrot, the overlay, the menu bar and the
/// stats.
///
/// `DictationController` calls these on the main actor, in the order the
/// observers were registered. Every method has an empty default, so an
/// observer implements only what it needs. New behaviour that reacts to a
/// dictation is an observer, not a branch in the controller.
@MainActor
package protocol DictationObserver: AnyObject {
    /// Recording started.
    func dictationStarted()
    /// The hotkey was released; the capture is being transcribed.
    func dictationTranscribing()
    /// The transcript was delivered.
    func dictationFinished(_ result: DictationResult)
    /// Nothing was delivered: capture failed (`CaptureError`), no audio
    /// (`DictationError.noAudio`), the recording was discarded
    /// (`DictationError.cancelled`), the transcriber threw, or the
    /// `TranscriptDelivery` threw (`DeliveryError` from `CursorDelivery`).
    func dictationFailed(_ error: Error)
}

extension DictationObserver {
    package func dictationStarted() {}
    package func dictationTranscribing() {}
    package func dictationFinished(_ result: DictationResult) {}
    package func dictationFailed(_ error: Error) {}
}
