import AVFoundation
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import SwivelCore

// Gap tests from the M4 mutation run: boundaries and check order the AC 8/10 tests left open.

private func fourCC(_ s: String) -> FourCharCode { s.utf8.reduce(0) { $0 << 8 | FourCharCode($1) } }

private func healthyMov(_ change: (inout AVProbe) -> Void = { _ in }) -> AVProbe {
    var p = AVProbe()
    p.contentType = .quickTimeMovie
    p.opened = true
    p.playable = true
    p.duration = 2
    p.hasVideo = true
    p.hasAudio = true
    p.videoCodec = fourCC("avc1")
    p.audioCodec = kAudioFormatMPEG4AAC
    p.videoSize = CGSize(width: 320, height: 240)
    p.audioRate = 44100
    p.audioChannels = 1
    change(&p)
    return p
}

// 2^31 s at 1 Hz mono 16-bit is exactly 4 GiB of samples: the limit is inclusive and exactly 4 GiB.
@Test func wavLimitIsExactlyFourGiB() {
    let half = Double(1 << 31)
    #expect(wavTooLarge(duration: half, rate: 1, channels: 1))
    #expect(!wavTooLarge(duration: half - 1, rate: 1, channels: 1))
    // 4e9 bytes is under 4 GiB, so it still fits.
    #expect(!wavTooLarge(duration: 2e9, rate: 1, channels: 1))
}

// The size check uses the clamped rate and channels, so a hostile rate can't hide a too-long file.
@Test func wavLimitUsesClampedFormat() {
    let tenHours = 36_000.0
    for rate in [Double.nan, 0, -1, .infinity] {
        // 10 h at 44.1 kHz mono (the fallback) is ~3.2 GB: fits.
        #expect(avDecision(healthyMov { $0.duration = tenHours; $0.audioRate = rate }, .wav) == .encode, "rate \(rate)")
        #expect(avDecision(healthyMov { $0.duration = 1e9; $0.audioRate = rate }, .wav) == .fail("too long for WAV (4 GB limit)"), "rate \(rate)")
    }
    // 4 h at 48 kHz fits as stereo but not as 6 channels, so 6 must count as 2.
    #expect(avDecision(healthyMov { $0.duration = 14_400; $0.audioRate = 48_000; $0.audioChannels = 6 }, .wav) == .encode)
    // 50 000 s at 48 kHz is over only if 0 channels count as 1.
    #expect(avDecision(healthyMov { $0.duration = 50_000; $0.audioRate = 48_000; $0.audioChannels = 0 }, .wav) == .fail("too long for WAV (4 GB limit)"))
}

// AC 10 order: open, DRM, tracks, playable. A missing track wins over "codec not supported".
@Test func missingTrackIsCheckedBeforePlayable() {
    let audioOnlyUnplayable = healthyMov { $0.hasVideo = false; $0.videoCodec = nil; $0.playable = false }
    for t in [AVTarget.mp4, .hevc, .mov, .gif] { #expect(avDecision(audioOnlyUnplayable, t) == .skip(.noVideo)) }
    let videoOnlyUnplayable = healthyMov { $0.hasAudio = false; $0.audioCodec = nil; $0.playable = false }
    for t in [AVTarget.m4a, .wav] { #expect(avDecision(videoOnlyUnplayable, t) == .skip(.noAudio)) }
    // Playable before duration and size.
    #expect(avDecision(healthyMov { $0.playable = false; $0.duration = .nan; $0.videoSize = .zero }, .mp4) == .skip(.codec))
    // A file that won't open is "not supported" even if a flag says protected.
    #expect(avDecision(healthyMov { $0.opened = false; $0.protected = true }, .mp4) == .skip(.notSupported))
}

/// An audio file in a rate and channel count the shared fixture can't make; closed when the AVAudioFile goes out of scope.
private func tone(_ url: URL, rate: Double, channels: AVAudioChannelCount, settings: [String: Any]) throws {
    let layout = AVAudioChannelLayout(layoutTag: channels == 6 ? kAudioChannelLayoutTag_MPEG_5_1_A : kAudioChannelLayoutTag_DiscreteInOrder | channels)!
    let format = AVAudioFormat(standardFormatWithSampleRate: rate, channelLayout: layout)
    var all = settings
    all[AVSampleRateKey] = rate
    all[AVNumberOfChannelsKey] = channels
    if channels > 2 { all[AVChannelLayoutKey] = Data(bytes: layout.layout, count: MemoryLayout<AudioChannelLayout>.size) }
    let file = try AVAudioFile(forWriting: url, settings: all, commonFormat: .pcmFormatFloat32, interleaved: false)
    let frames = AVAudioFrameCount(rate)  // 1 s
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
    buffer.frameLength = frames
    for c in 0..<Int(channels) {
        for i in 0..<Int(frames) { buffer.floatChannelData![c][i] = Float(0.2 * sin(Double(i) * 2 * .pi * 440 / rate)) }
    }
    try file.write(from: buffer)
}

private func wavFormatOf(_ url: URL) async throws -> AudioStreamBasicDescription {
    let track = try #require(try await AVURLAsset(url: url).loadTracks(withMediaType: .audio).first)
    let desc = try #require(try await track.load(.formatDescriptions).first)
    return try #require(CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee)
}

// AC 8 on real files: the WAV keeps the source's rate, and channels clamp to 1...2 (fixtures are all 44.1 kHz mono).
@Test(arguments: [
    ("stereo.m4a", 48_000.0, AVAudioChannelCount(2), UInt32(2)),
    ("low.m4a", 22_050, 1, 1),
    ("surround.caf", 48_000, 6, 2),
])
func wavKeepsRateAndClampsChannels(name: String, rate: Double, channels: AVAudioChannelCount, expected: UInt32) async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let src = dir.appendingPathComponent(name)
    let aac: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC]
    let pcm: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
                              AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false]
    try tone(src, rate: rate, channels: channels, settings: name.hasSuffix(".caf") ? pcm : aac)
    let p = await Converter.probe(src)
    #expect(p.audioRate == rate && p.audioChannels == channels, "probe \(p.audioRate) \(p.audioChannels)")
    let outcome = await Converter.convertAV(src, to: .wav)
    guard case .converted(_, let outputs) = outcome, let out = outputs.first else { Issue.record("\(outcome)"); return }
    let asbd = try await wavFormatOf(out)
    #expect(asbd.mSampleRate == rate)
    #expect(asbd.mChannelsPerFrame == expected)
    #expect(asbd.mBitsPerChannel == 16)
    #expect(abs(try await AVURLAsset(url: out).load(.duration).seconds - 1) < 0.05)
    #expect(try files(in: dir) == [name, src.deletingPathExtension().lastPathComponent + ".wav"])
}

// A .m4a that also holds video still needs extracting: only an audio-only AAC .m4a is already M4A.
@Test func m4aWithVideoIsNotAlreadyM4A() {
    let m4aWithVideo = healthyMov { $0.contentType = UTType(filenameExtension: "m4a") }
    #expect(avDecision(m4aWithVideo, .m4a) == .remux)
}
