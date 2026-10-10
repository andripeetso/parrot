import Foundation

package enum Engine: String, Codable {
    case whisperKit
    case parakeet
}

package struct TranscriptionModel: Codable {
    package let id: String
    package let displayName: String
    package let engine: Engine
    /// Engine-specific identifier (e.g. "openai_whisper-base.en" for WhisperKit).
    package let whisperKitID: String?
    package let sizeMB: Int
    package let languages: [String]
    package let recommended: Bool
}

package struct ModelsManifest: Codable {
    package let models: [TranscriptionModel]
}
