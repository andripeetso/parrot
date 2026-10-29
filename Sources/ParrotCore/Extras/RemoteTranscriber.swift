import Foundation

/// Sends the recording to a speech-to-text server on the LAN (the Omarchy box's
/// parrot-asr service: POST a WAV, get back `{"text": ...}`).
struct RemoteTranscriber: Transcriber {
    let endpoint: URL
    var modelID: String { "remote (\(endpoint.host ?? endpoint.absoluteString))" }

    private struct Response: Decodable { let text: String }

    /// The first connection after launch can fail with "offline" while macOS
    /// checks Local Network access, so retry that error once.
    func transcribe(_ audio: [Float], context: TranscriptionContext) async throws -> Transcript {
        do {
            return Transcript(text: try await post(audio))
        } catch let error as URLError where error.code == .notConnectedToInternet {
            try await Task.sleep(nanoseconds: 300_000_000)
            return Transcript(text: try await post(audio))
        }
    }

    /// Opens the connection early so the first dictation doesn't pay for it.
    func warmUp() async {
        var request = URLRequest(url: endpoint.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("health"))
        request.timeoutInterval = 5
        for attempt in 1...10 {
            if (try? await URLSession.shared.data(for: request)) != nil {
                Log.info("✓ server reachable (attempt \(attempt))")
                return
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        Log.warning("server not reachable at startup; using the on-device model until it is")
    }

    private func post(_ audio: [Float]) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        // Fail over quickly when the box is off, but give long recordings time to finish.
        let seconds = Double(audio.count) / AudioCapture.targetSampleRate
        request.timeoutInterval = 4 + seconds * 0.25
        let body = WAVWriter.data(samples: audio, sampleRate: Int(AudioCapture.targetSampleRate))
        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw RemoteTranscriberError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return try JSONDecoder().decode(Response.self, from: data).text
    }
}

enum RemoteTranscriberError: Error {
    case badStatus(Int)
}
