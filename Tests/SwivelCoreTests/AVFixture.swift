import AVFoundation
import CoreMedia
import Foundation
import Testing

/// Writes small media fixtures in-test with AVAssetWriter: video at 10 fps, a 440 Hz mono tone at 44.1 kHz.
enum AVFixture {
    enum Video { case h264, hevc }

    /// `frames` defaults to 10 per second; `audioSeconds` to `seconds`; `fileType` .wav writes 16-bit LPCM audio, every other type AAC.
    static func write(
        _ name: String, in dir: URL, video: Video? = .h264, audio: Bool = true, size: CGSize = CGSize(width: 320, height: 240),
        seconds: Double = 2, audioSeconds: Double? = nil, frames: Int? = nil, transform: CGAffineTransform = .identity,
        fileType: AVFileType = .mov
    ) async throws -> URL {
        let url = dir.appendingPathComponent(name)
        let writer = try AVAssetWriter(outputURL: url, fileType: fileType)
        var lanes: [(input: AVAssetWriterInput, steps: [() -> Bool])] = []

        if let video {
            let settings: [String: Any] = [
                AVVideoCodecKey: video == .h264 ? AVVideoCodecType.h264 : AVVideoCodecType.hevc,
                AVVideoWidthKey: size.width, AVVideoHeightKey: size.height,
            ]
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            input.transform = transform
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: size.width, kCVPixelBufferHeightKey as String: size.height,
            ])
            #expect(writer.canAdd(input))
            writer.add(input)
            let count = frames ?? Int((seconds * 10).rounded())
            lanes.append((input, (0..<count).map { i in {
                let t = count > 1 ? seconds * Double(i) / Double(count) : 0
                var buffer: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
                CVPixelBufferLockBaseAddress(buffer!, [])
                memset(CVPixelBufferGetBaseAddress(buffer!), Int32(i * 25 % 256), CVPixelBufferGetDataSize(buffer!))
                CVPixelBufferUnlockBaseAddress(buffer!, [])
                return adaptor.append(buffer!, withPresentationTime: CMTime(seconds: t, preferredTimescale: 600))
            } }))
        }

        if audio {
            let pcm = fileType == .wav
            let settings: [String: Any] = pcm
                ? [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1,
                   AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
                   AVLinearPCMIsNonInterleaved: false]
                : [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1]
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
            #expect(writer.canAdd(input))
            writer.add(input)
            var asbd = AudioStreamBasicDescription(
                mSampleRate: 44100, mFormatID: kAudioFormatLinearPCM, mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
                mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
            var format: CMAudioFormatDescription?
            CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil,
                                           extensions: nil, formatDescriptionOut: &format)
            let chunk = 4410, chunks = Int(((audioSeconds ?? seconds) * 10).rounded())
            lanes.append((input, (0..<chunks).map { c in {
                var samples = (0..<chunk).map { Int16(8000 * sin(Double(c * chunk + $0) * 2 * .pi * 440 / 44100)) }
                var block: CMBlockBuffer?
                CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: chunk * 2, blockAllocator: nil,
                                                   customBlockSource: nil, offsetToData: 0, dataLength: chunk * 2, flags: 0, blockBufferOut: &block)
                CMBlockBufferReplaceDataBytes(with: &samples, blockBuffer: block!, offsetIntoDestination: 0, dataLength: chunk * 2)
                var sample: CMSampleBuffer?
                CMAudioSampleBufferCreateReadyWithPacketDescriptions(
                    allocator: nil, dataBuffer: block!, formatDescription: format!, sampleCount: chunk,
                    presentationTimeStamp: CMTime(value: Int64(c * chunk), timescale: 44100), packetDescriptions: nil, sampleBufferOut: &sample)
                return input.append(sample!)
            } }))
        }

        #expect(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        // Round-robin, never blocking on one input: the writer may hold one back until the other catches up.
        var next = lanes.map { _ in 0 }
        while writer.status == .writing, lanes.indices.contains(where: { next[$0] < lanes[$0].steps.count }) {
            var progressed = false
            for l in lanes.indices where next[l] < lanes[l].steps.count && lanes[l].input.isReadyForMoreMediaData {
                #expect(lanes[l].steps[next[l]](), "append failed: \(String(describing: writer.error))")
                next[l] += 1
                progressed = true
                // Finish a lane at once: the writer holds the other input back while waiting for more of this one.
                if next[l] == lanes[l].steps.count { lanes[l].input.markAsFinished() }
            }
            if !progressed { try await Task.sleep(for: .milliseconds(1)) }
        }
        writer.endSession(atSourceTime: CMTime(seconds: max(seconds, audio ? audioSeconds ?? 0 : 0), preferredTimescale: 600))
        await writer.finishWriting()
        #expect(writer.status == .completed, "\(String(describing: writer.error))")
        return url
    }

    /// Four-char codec of the first track of `type`, e.g. "avc1", or nil.
    static func codec(_ url: URL, _ type: AVMediaType) async throws -> String? {
        guard let track = try await AVURLAsset(url: url).loadTracks(withMediaType: type).first,
              let desc = try await track.load(.formatDescriptions).first
        else { return nil }
        let code = CMFormatDescriptionGetMediaSubType(desc).bigEndian
        return withUnsafeBytes(of: code) { String(decoding: $0, as: UTF8.self) }
    }

    static func duration(_ url: URL) async throws -> Double {
        try await AVURLAsset(url: url).load(.duration).seconds
    }
}
