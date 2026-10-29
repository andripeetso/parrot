import AVFoundation
import Foundation

enum AudioFileLoader {
    enum LoaderError: Error {
        case invalidFormat
        case conversionFailed(Error?)
    }

    static func load(url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let sourceFormat = file.processingFormat
        guard sourceFormat.sampleRate > 0, sourceFormat.channelCount > 0 else {
            throw LoaderError.invalidFormat
        }

        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: AudioCapture.targetSampleRate,
            channels: 1,
            interleaved: false
        )!
        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw LoaderError.invalidFormat
        }

        var samples: [Float] = []
        let chunkSize: AVAudioFrameCount = 16_384
        while file.framePosition < file.length {
            let framesToRead = min(chunkSize, AVAudioFrameCount(file.length - file.framePosition))
            guard let input = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: framesToRead) else {
                throw LoaderError.invalidFormat
            }
            try file.read(into: input, frameCount: framesToRead)
            guard input.frameLength > 0 else { break }

            let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
            let outputCapacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 128
            guard let output = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: outputCapacity
            ) else {
                throw LoaderError.invalidFormat
            }

            var supplied = false
            var conversionError: NSError?
            let status = converter.convert(to: output, error: &conversionError) { _, status in
                guard !supplied else {
                    status.pointee = .noDataNow
                    return nil
                }
                supplied = true
                status.pointee = .haveData
                return input
            }
            guard status != .error, let channelData = output.floatChannelData else {
                throw LoaderError.conversionFailed(conversionError)
            }
            samples.append(contentsOf: UnsafeBufferPointer(start: channelData[0], count: Int(output.frameLength)))
        }
        return samples
    }
}
