import AVFoundation
import CoreMedia
import Foundation
import Testing

/// Writes small media fixtures in-test with AVAssetWriter: video at 10 fps, a 440 Hz mono tone at 44.1 kHz.
enum AVFixture {
    enum Video { case h264, hevc }

    /// `frames` defaults to 10 per second; `audioSeconds` to `seconds`; `fileType` .wav writes 16-bit LPCM audio, every other type AAC.
    /// `audioTracks` identical tracks of `channels` each (6 is 5.1).
    static func write(
        _ name: String, in dir: URL, video: Video? = .h264, audio: Bool = true, size: CGSize = CGSize(width: 320, height: 240),
        seconds: Double = 2, audioSeconds: Double? = nil, frames: Int? = nil, transform: CGAffineTransform = .identity,
        fileType: AVFileType = .mov, audioTracks: Int = 1, channels: Int = 1, pcm: Bool = false
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

        for _ in 0..<(audio ? audioTracks : 0) {
            let pcm = pcm || fileType == .wav
            var layout = AudioChannelLayout()
            layout.mChannelLayoutTag = channels == 6 ? kAudioChannelLayoutTag_MPEG_5_1_D : kAudioChannelLayoutTag_DiscreteInOrder | UInt32(channels)
            var settings: [String: Any] = pcm
                ? [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44100, AVNumberOfChannelsKey: channels,
                   AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
                   AVLinearPCMIsNonInterleaved: false]
                : [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: channels]
            if channels > 2 { settings[AVChannelLayoutKey] = Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size) }
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
            #expect(writer.canAdd(input))
            writer.add(input)
            var asbd = AudioStreamBasicDescription(
                mSampleRate: 44100, mFormatID: kAudioFormatLinearPCM, mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
                mBytesPerPacket: UInt32(2 * channels), mFramesPerPacket: 1, mBytesPerFrame: UInt32(2 * channels),
                mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 16, mReserved: 0)
            var format: CMAudioFormatDescription?
            withUnsafePointer(to: &layout) { l in
                _ = CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: channels > 2 ? MemoryLayout<AudioChannelLayout>.size : 0,
                                                   layout: channels > 2 ? l : nil, magicCookieSize: 0, magicCookie: nil,
                                                   extensions: nil, formatDescriptionOut: &format)
            }
            let chunk = 4410, bytes = chunk * 2 * channels, chunks = Int(((audioSeconds ?? seconds) * 10).rounded())
            lanes.append((input, (0..<chunks).map { c in {
                // Interleaved: the same sample on every channel of a frame.
                var samples = (0..<chunk * channels).map { Int16(8000 * sin(Double(c * chunk + $0 / channels) * 2 * .pi * 440 / 44100)) }
                var block: CMBlockBuffer?
                CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: bytes, blockAllocator: nil,
                                                   customBlockSource: nil, offsetToData: 0, dataLength: bytes, flags: 0, blockBufferOut: &block)
                CMBlockBufferReplaceDataBytes(with: &samples, blockBuffer: block!, offsetIntoDestination: 0, dataLength: bytes)
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
