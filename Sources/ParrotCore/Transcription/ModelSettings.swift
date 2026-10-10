/// Transcription model preferences.
///
/// The `settings.json` field for this feature; see `Settings`. Give each new
/// field a default and decode it in `init(from:)` with
/// `decodeIfPresent(…) ?? default`, so older files and `{}` still load.
package struct ModelSettings: Codable, Equatable {
    /// A `ModelRegistry` id, or nil for the recommended model. An id the
    /// registry doesn't know falls back to the recommended model at startup.
    package var id: String?

    package init() {}

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
    }
}
