/// Input device preferences (#44). Empty until that feature lands.
///
/// The `settings.json` field for this feature; see `Settings`. Give each new
/// field a default and decode it in `init(from:)` with
/// `decodeIfPresent(…) ?? default`, so older files and `{}` still load.
package struct AudioSettings: Codable, Equatable {
    package init() {}

    package init(from decoder: Decoder) throws {}
}
