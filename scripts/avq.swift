// QA helper for scripts/qa.sh, compiled once per run.
//   avq mk <out> <seconds> <frames> <audio 0|1> <rotate 0|1>   H.264 320x240 (+ AAC tone) at <out>
//   avq codec <file> video|audio                               four-char codec of the first track, or "none"
//   avq gif <file>                                             "<frames> <width> <height> <delay> <loop>"
import AVFoundation
import ImageIO

let a = CommandLine.arguments
switch a[1] {
case "mk":
    let url = URL(fileURLWithPath: a[2]), seconds = Double(a[3])!, frames = Int(a[4])!, audio = a[5] == "1"
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 320, AVVideoHeightKey: 240])
    if a[6] == "1" { video.transform = CGAffineTransform(rotationAngle: .pi / 2) }
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 240])
    writer.add(video)
    var lanes: [(AVAssetWriterInput, [() -> Bool])] = [(video, (0..<frames).map { i in {
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
        CVPixelBufferLockBaseAddress(buffer!, [])
        memset(CVPixelBufferGetBaseAddress(buffer!), Int32(i * 25 % 256), CVPixelBufferGetDataSize(buffer!))
        CVPixelBufferUnlockBaseAddress(buffer!, [])
        let t = frames > 1 ? seconds * Double(i) / Double(frames) : 0
        return adaptor.append(buffer!, withPresentationTime: CMTime(seconds: t, preferredTimescale: 600))
    } })]
    if audio {
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1])
        writer.add(input)
        var asbd = AudioStreamBasicDescription(
            mSampleRate: 44100, mFormatID: kAudioFormatLinearPCM, mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil,
                                       extensions: nil, formatDescriptionOut: &format)
        let chunk = 4410
        lanes.append((input, (0..<Int(seconds * 10)).map { c in {
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
    guard writer.startWriting() else { fatalError("\(String(describing: writer.error))") }
    writer.startSession(atSourceTime: .zero)
    // Round-robin, finishing each input as soon as it runs out, so neither waits on the other.
    var next = lanes.map { _ in 0 }
    while writer.status == .writing, lanes.indices.contains(where: { next[$0] < lanes[$0].1.count }) {
        var progressed = false
        for l in lanes.indices where next[l] < lanes[l].1.count && lanes[l].0.isReadyForMoreMediaData {
            precondition(lanes[l].1[next[l]](), "append failed")
            next[l] += 1
            progressed = true
            if next[l] == lanes[l].1.count { lanes[l].0.markAsFinished() }
        }
        if !progressed { try await Task.sleep(for: .milliseconds(1)) }
    }
    writer.endSession(atSourceTime: CMTime(seconds: seconds, preferredTimescale: 600))
    await writer.finishWriting()
    guard writer.status == .completed else { fatalError("\(String(describing: writer.error))") }
case "codec":
    let track = try await AVURLAsset(url: URL(fileURLWithPath: a[2])).loadTracks(withMediaType: a[3] == "video" ? .video : .audio).first
    let code = try await track?.load(.formatDescriptions).first.map { CMFormatDescriptionGetMediaSubType($0).bigEndian }
    print(code.map { c in withUnsafeBytes(of: c) { String(decoding: $0, as: UTF8.self) } } ?? "none")
case "gif":
    let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: a[2]) as CFURL, nil)!
    let image = CGImageSourceCreateImageAtIndex(src, 0, nil)!
    let gif = { (p: CFDictionary?) in (p as? [CFString: Any])?[kCGImagePropertyGIFDictionary] as? [CFString: Any] }
    let delay = gif(CGImageSourceCopyPropertiesAtIndex(src, 0, nil))?[kCGImagePropertyGIFDelayTime] ?? "?"
    let loop = gif(CGImageSourceCopyProperties(src, nil))?[kCGImagePropertyGIFLoopCount] ?? "?"
    print(CGImageSourceGetCount(src), image.width, image.height, delay, loop)
default:
    fatalError("unknown mode \(a[1])")
}
