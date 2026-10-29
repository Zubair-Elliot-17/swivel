import AVFoundation
import CoreMedia
import Foundation

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
}
