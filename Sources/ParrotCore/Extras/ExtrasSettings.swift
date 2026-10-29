import Foundation

/// Andri's additions in `settings.json`: saved recordings, start/stop sounds,
/// the History and file-drop keys, and an optional LAN transcription server.
struct ExtrasSettings: Codable, Equatable {
    /// How many dictations stay in History (audio and transcript).
    var keepRecordings = 10
    /// A short sound when recording starts and stops.
    var sounds = true
    /// Opens History.
    var historyKey: FunctionKey = .f14
    /// Opens the file drop box.
    var fileDropKey: FunctionKey = .f15
    /// Tried before the on-device model: POST a WAV, get back `{"text": ...}`.
    /// Nil or empty for on-device only.
    var server: String?

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        keepRecordings = max(1, try c.decodeIfPresent(Int.self, forKey: .keepRecordings) ?? 10)
        sounds = try c.decodeIfPresent(Bool.self, forKey: .sounds) ?? true
        historyKey = try c.decodeIfPresent(String.self, forKey: .historyKey).flatMap(FunctionKey.init(rawValue:)) ?? .f14
        fileDropKey = try c.decodeIfPresent(String.self, forKey: .fileDropKey).flatMap(FunctionKey.init(rawValue:)) ?? .f15
        server = try c.decodeIfPresent(String.self, forKey: .server)
    }

    /// The server's URL, or nil when it is off or not a URL with a host.
    var serverURL: URL? {
        guard let server, let url = URL(string: server), url.host != nil else { return nil }
        return url
    }
}

/// A plain function key for a global shortcut, or off.
enum FunctionKey: String, Codable, CaseIterable {
    case f14, f15, f16, off

    var displayName: String { self == .off ? "Off" : rawValue.uppercased() }

    /// `kVK_F14`, `kVK_F15`, `kVK_F16`.
    var keycode: UInt32? {
        switch self {
        case .f14: return 107
        case .f15: return 113
        case .f16: return 106
        case .off: return nil
        }
    }

    /// "  (F14)" after a menu title, or "" when off.
    var menuSuffix: String { self == .off ? "" : "  (\(displayName))" }
}
