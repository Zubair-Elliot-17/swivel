import AVFoundation
import CoreMedia
import Foundation
import ImageIO
import UniformTypeIdentifiers

extension Converter {
    /// Decodes every audio track, mixed, to 16-bit LPCM at most stereo, into a WAV at `url`.
    /// `canAdd` guards each add: a bad add raises an ObjC exception.
    static func writeWAV(_ source: URL, to url: URL, probe p: AVProbe, progress: @Sendable (Double) -> Void) async throws {
        let asset = AVURLAsset(url: source)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        let format = wavFormat(rate: p.audioRate, channels: p.audioChannels)
        let pcm: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: format.rate, AVNumberOfChannelsKey: format.channels,
        ]
        let reader = try AVAssetReader(asset: asset)
        let mix = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: pcm)
        guard reader.canAdd(mix) else { throw ConvertError("couldn't read audio") }
        reader.add(mix)
        let writer = try AVAssetWriter(outputURL: url, fileType: .wav)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: pcm)
        guard writer.canAdd(input) else { throw ConvertError("couldn't write WAV") }
        writer.add(input)
        guard reader.startReading() else { throw reader.error ?? ConvertError("couldn't read audio") }
        guard writer.startWriting() else {
            reader.cancelReading()
            throw writer.error ?? ConvertError("couldn't write WAV")
        }
        writer.startSession(atSourceTime: .zero)
        // copyNextSampleBuffer blocks while it decodes, so it runs on a private queue, never on the cooperative pool
        // (blocked there beside Vision OCR it starved the pool). shortcut: `mix` is touched only on that queue from here on.
        nonisolated(unsafe) let output = mix
        let queue = DispatchQueue(label: "dev.zubair.swivel.wav-reader")
        func next() async -> CMSampleBuffer? {
            await withCheckedContinuation { done in
                queue.async {
                    nonisolated(unsafe) let buffer = output.copyNextSampleBuffer()  // fresh, handed over once
                    done.resume(returning: buffer)
                }
            }
        }
        do {
            while let buffer = await next() {
                try Task.checkCancellation()
                while !input.isReadyForMoreMediaData {
                    guard writer.status == .writing else { throw writer.error ?? ConvertError("couldn't write WAV") }
                    try await Task.sleep(for: .milliseconds(5))
                }
                guard input.append(buffer) else { throw writer.error ?? ConvertError("couldn't write WAV") }
                let written = (CMSampleBufferGetPresentationTimeStamp(buffer) + CMSampleBufferGetDuration(buffer)).seconds
                if written.isFinite { progress(min(written / p.duration, 1)) }
            }
            guard reader.status == .completed else { throw reader.error ?? ConvertError("couldn't read audio") }
            input.markAsFinished()
            await writer.finishWriting()
            guard writer.status == .completed else { throw writer.error ?? ConvertError("couldn't write WAV") }
        } catch {
            reader.cancelReading()
            writer.cancelWriting()
            throw error
        }
        progress(1)
    }

    /// A looping GIF at 10 fps, long side at most 480 px (never upscaled), from at most 30 s of the video track (`avDecision` caps it).
    /// Frames go into the destination as they arrive; the GIF itself is built in memory.
    static func makeGIF(_ source: URL, probe p: AVProbe, progress: @Sendable (Double) -> Void) async throws -> Data {
        // `avDecision` checked the size finite and > 0, the video start finite >= 0 and its duration in 0...30 s.
        let side = min(480, max(abs(p.videoSize.width), abs(p.videoSize.height)))
        guard let count = Int(exactly: max(1, min(gifMaxSeconds * 10, (p.videoDuration * 10).rounded(.down)))) else {
            throw ConvertError("couldn't make GIF")
        }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: source))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = CGSize(width: side, height: side)
        defer { generator.cancelAllCGImageGeneration() }

        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, UTType.gif.identifier as CFString, count, nil)
        else { throw ConvertError("couldn't make GIF") }
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        // 0.1 s is exact in GIF's 1/100 s delays, so it plays at a true 10 fps.
        let frame = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary
        var done = 0
        for await result in generator.images(for: (0..<count).map { CMTime(seconds: p.videoStart, preferredTimescale: 600) + CMTime(value: CMTimeValue($0), timescale: 10) }) {
            try Task.checkCancellation()
            CGImageDestinationAddImage(dest, try result.image, frame)
            done += 1
            progress(Double(done) / Double(count))
        }
        try Task.checkCancellation()
        guard done == count, CGImageDestinationFinalize(dest) else { throw ConvertError("couldn't make GIF") }
        return data as Data
    }
}
