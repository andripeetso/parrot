/// An error with a short message the user should see, for example in the
/// overlay. Anything else reaching `dictationFailed` is only logged.
public protocol UserFacingError: Error {
    /// One line, actionable, never containing transcript text.
    var userMessage: String { get }
}
