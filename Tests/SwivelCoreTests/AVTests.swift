import AVFoundation
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import SwivelCore

private func fourCC(_ s: String) -> FourCharCode { s.utf8.reduce(0) { $0 << 8 | FourCharCode($1) } }

/// A healthy 2 s H.264 + AAC MOV, 320x240; each test changes one field.
private func movProbe(_ change: (inout AVProbe) -> Void = { _ in }) -> AVProbe {
    var p = AVProbe()
    p.contentType = .quickTimeMovie
    p.opened = true
    p.playable = true
    p.duration = 2
    (p.videoStart, p.videoDuration) = (0, 2)
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

private let videoTargets: [AVTarget] = [.mp4, .hevc, .mov, .gif]
private let audioTargets: [AVTarget] = [.m4a, .wav]
private let huge = Double(CMTime(value: .max, timescale: 1).seconds)

// MARK: Pure decision table (AC 10)

@Test func healthyMovRoutes() {
    let p = movProbe()
    #expect(avDecision(p, .mp4) == .remux)
    #expect(avDecision(p, .hevc) == .encode)
    #expect(avDecision(p, .mov) == .skip(.alreadyAV(.mov)))
    #expect(avDecision(p, .gif) == .encode)
    #expect(avDecision(p, .m4a) == .remux)
    #expect(avDecision(p, .wav) == .encode)
}

@Test func codecsPickRemuxOrEncode() {
    let hvc1 = movProbe { $0.videoCodec = fourCC("hvc1") }
    #expect(avDecision(hvc1, .mp4) == .encode)
    #expect(avDecision(hvc1, .hevc) == .remux)
    // Q7: hev1 plays badly in QuickTime, so it re-encodes.
    #expect(avDecision(movProbe { $0.videoCodec = fourCC("hev1") }, .hevc) == .encode)
    #expect(avDecision(movProbe { $0.audioCodec = kAudioFormatLinearPCM }, .m4a) == .encode)
    #expect(avDecision(movProbe { $0.contentType = .mpeg4Movie }, .mov) == .remux)
}

@Test func alreadyTargets() {
    #expect(avDecision(movProbe { $0.contentType = .mpeg4Movie }, .mp4) == .skip(.alreadyAV(.mp4)))
    #expect(avDecision(movProbe { $0.contentType = .mpeg4Movie; $0.videoCodec = fourCC("hvc1") }, .hevc) == .skip(.alreadyAV(.hevc)))
    // An HEVC .mp4 on MP4 means "make it H.264", so it isn't already MP4.
    #expect(avDecision(movProbe { $0.contentType = .mpeg4Movie; $0.videoCodec = fourCC("hvc1") }, .mp4) == .encode)
    let m4a = movProbe { $0.contentType = UTType(filenameExtension: "m4a"); $0.hasVideo = false; $0.videoCodec = nil }
    #expect(avDecision(m4a, .m4a) == .skip(.alreadyAV(.m4a)))
    let wav = movProbe { $0.contentType = .wav; $0.hasVideo = false; $0.audioCodec = kAudioFormatLinearPCM }
    #expect(avDecision(wav, .wav) == .skip(.alreadyAV(.wav)))
    #expect(avDecision(wav, .m4a) == .encode)
}

@Test(arguments: AVTarget.allCases)
func openFailures(target: AVTarget) {
    #expect(avDecision(movProbe { $0.opened = false }, target) == .skip(.notSupported))
    #expect(avDecision(movProbe { $0.opened = false; $0.errorCode = -11828 }, target) == .skip(.notSupported))
    #expect(avDecision(movProbe { $0.opened = false; $0.errorCode = -11829 }, target) == .skip(.notSupported))
    #expect(avDecision(movProbe { $0.opened = false; $0.errorCode = -11831 }, target) == .skip(.drm))
    #expect(avDecision(movProbe { $0.opened = false; $0.errorCode = -11835 }, target) == .skip(.drm))
    #expect(avDecision(movProbe { $0.opened = false; $0.errorCode = -11833 }, target) == .skip(.codec))
}

// Q1: an asset that opens but can't be timed is "not supported by macOS".
@Test(arguments: AVTarget.allCases)
func badDurationsSkip(target: AVTarget) {
    for d in [0, -1, Double.nan, .infinity, -.infinity, CMTime.indefinite.seconds, CMTime.invalid.seconds, CMTime.positiveInfinity.seconds] {
        #expect(avDecision(movProbe { $0.duration = d }, target) == .skip(.notSupported), "duration \(d)")
    }
}

@Test func hugeFiniteDurations() {
    #expect(huge > 9e18 && huge.isFinite)
    let p = movProbe { $0.duration = huge; $0.videoDuration = huge }
    #expect(avDecision(p, .gif) == .fail("too long for GIF (max 30 s)"))
    #expect(avDecision(p, .wav) == .fail("too long for WAV (4 GB limit)"))
    // No cap on streamed re-encodes (design finding 7).
    #expect(avDecision(p, .mp4) == .remux)
    #expect(avDecision(p, .hevc) == .encode)
    #expect(avDecision(p, .mov) == .skip(.alreadyAV(.mov)))
    #expect(avDecision(p, .m4a) == .remux)
    #expect(avDecision(movProbe { $0.duration = 30; $0.videoDuration = 30 }, .gif) == .encode)
    #expect(avDecision(movProbe { $0.duration = 30.01; $0.videoDuration = 30.01 }, .gif) == .fail("too long for GIF (max 30 s)"))
}

@Test func videoSizes() {
    // Rotation can make a side negative: abs() per side, then used.
    #expect(avDecision(movProbe { $0.videoSize = CGSize(width: -240, height: 320) }, .gif) == .encode)
    for size in [CGSize.zero, CGSize(width: 320, height: 0), CGSize(width: CGFloat.nan, height: 240),
                 CGSize(width: 320, height: CGFloat.infinity), CGSize(width: -CGFloat.infinity, height: 240)] {
        for target in videoTargets {
            #expect(avDecision(movProbe { $0.videoSize = size }, target) == .skip(.codec), "\(size) \(target)")
        }
        // Audio extraction never reads the picture.
        #expect(avDecision(movProbe { $0.videoSize = size }, .m4a) == .remux)
    }
}

@Test func missingTracks() {
    let none = movProbe { $0.hasVideo = false; $0.hasAudio = false; $0.videoCodec = nil; $0.audioCodec = nil }
    for t in videoTargets { #expect(avDecision(none, t) == .skip(.noVideo)) }
    for t in audioTargets { #expect(avDecision(none, t) == .skip(.noAudio)) }
    let audioOnly = movProbe { $0.contentType = .mpeg4Movie; $0.hasVideo = false; $0.videoCodec = nil }
    for t in videoTargets { #expect(avDecision(audioOnly, t) == .skip(.noVideo)) }
    let videoOnly = movProbe { $0.hasAudio = false; $0.audioCodec = nil }
    for t in audioTargets { #expect(avDecision(videoOnly, t) == .skip(.noAudio)) }
}

// Q2: images and folders on an AV slice reuse "no video" / "no audio", before any AVAsset is made.
@Test func nonAVContentTypes() {
    for type in [UTType.png, .folder, .pdf, nil] {
        let p = movProbe { $0.contentType = type }
        for t in videoTargets { #expect(avDecision(p, t) == .skip(.noVideo)) }
        for t in audioTargets { #expect(avDecision(p, t) == .skip(.noAudio)) }
    }
}

@Test(arguments: AVTarget.allCases)
func undecodableAndProtected(target: AVTarget) {
    // VP9-in-MP4 opens and claims to be exportable but isn't playable: MOV passthrough included.
    let vp9 = movProbe { $0.contentType = .mpeg4Movie; $0.playable = false; $0.videoCodec = fourCC("vp09") }
    #expect(avDecision(vp9, target) == .skip(.codec))
    #expect(avDecision(movProbe { $0.protected = true }, target) == .skip(.drm))
    // DRM is checked before tracks and playability.
    #expect(avDecision(movProbe { $0.protected = true; $0.playable = false; $0.hasVideo = false; $0.hasAudio = false }, target) == .skip(.drm))
}

@Test func wavSizeLimitInDouble() {
    let tenHours = 36_000.0
    #expect(wavTooLarge(duration: tenHours, rate: 48_000, channels: 2))
    #expect(!wavTooLarge(duration: tenHours, rate: 8_000, channels: 1))
    #expect(wavTooLarge(duration: huge, rate: 48_000, channels: 2))
}

@Test func wavFormatIsClamped() {
    #expect(wavFormat(rate: 48_000, channels: 6) == (48_000, 2))
    #expect(wavFormat(rate: 22_050, channels: 0) == (22_050, 1))
    for bad in [0, -44_100, Double.nan, .infinity] { #expect(wavFormat(rate: bad, channels: 1) == (44_100, 1)) }
    #expect(wavFormat(rate: 44_100, channels: .max) == (44_100, 2))
}

// MARK: Probe on real fixtures (F rows)

@Test func garbageMP4IsNotSupported() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let bad = dir.appendingPathComponent("bad.mp4")
    try Data("junk".utf8).write(to: bad)
    let p = await Converter.probe(bad)
    #expect(!p.opened)
    for t in AVTarget.allCases { #expect(avDecision(p, t) == .skip(.notSupported)) }
}

@Test func probeReadsAMovFixture() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let p = await Converter.probe(try await AVFixture.write("clip.mov", in: dir))
    #expect(p.opened && p.playable && !p.protected && p.hasVideo && p.hasAudio)
    #expect(abs(p.duration - 2) < 0.05)
    #expect(p.videoCodec == fourCC("avc1"))
    #expect(p.audioCodec == kAudioFormatMPEG4AAC)
    #expect(p.videoSize == CGSize(width: 320, height: 240))
    #expect(p.audioRate == 44100 && p.audioChannels == 1)
    #expect(p.contentType == .quickTimeMovie)
}

@Test func probeAppliesTheRotation() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let url = try await AVFixture.write("rot.mov", in: dir, transform: CGAffineTransform(rotationAngle: .pi / 2))
    let p = await Converter.probe(url)
    #expect(abs(p.videoSize.width) == 240 && abs(p.videoSize.height) == 320)
    #expect(avDecision(p, .gif) == .encode)
}

@Test func audioOnlyFilesHaveNoVideo() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let m4a = try await AVFixture.write("voice.m4a", in: dir, video: nil, fileType: .m4a)
    let mp4 = try await AVFixture.write("voice.mp4", in: dir, video: nil, fileType: .mp4)
    for url in [m4a, mp4] {
        let p = await Converter.probe(url)
        for t in videoTargets { #expect(avDecision(p, t) == .skip(.noVideo), "\(url.lastPathComponent) \(t)") }
    }
    #expect(avDecision(await Converter.probe(m4a), .m4a) == .skip(.alreadyAV(.m4a)))
    #expect(avDecision(await Converter.probe(mp4), .m4a) == .remux)
}

@Test func videoOnlyFileHasNoAudio() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let p = await Converter.probe(try await AVFixture.write("mute.mov", in: dir, audio: false))
    for t in audioTargets { #expect(avDecision(p, t) == .skip(.noAudio)) }
}

@Test func longClipFailsGIF() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let p = await Converter.probe(try await AVFixture.write("long.mov", in: dir, audio: false, seconds: 31, frames: 2))
    #expect(abs(p.duration - 31) < 0.05)
    #expect(avDecision(p, .gif) == .fail("too long for GIF (max 30 s)"))
}

@Test func wavFixtureIsAlreadyWAV() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let p = await Converter.probe(try await AVFixture.write("voice.wav", in: dir, video: nil, fileType: .wav))
    #expect(p.audioCodec == kAudioFormatLinearPCM)
    #expect(avDecision(p, .wav) == .skip(.alreadyAV(.wav)))
    #expect(avDecision(p, .m4a) == .encode)
}

@Test func folderAndImageSkipBeforeOpening() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let png = try write(.png, in: dir)
    for url in [dir, png] {
        let p = await Converter.probe(url)
        #expect(!p.opened)
        #expect(avDecision(p, .mp4) == .skip(.noVideo))
        #expect(avDecision(p, .wav) == .skip(.noAudio))
    }
}
