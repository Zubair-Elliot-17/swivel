import AVFoundation
import Foundation
import Testing
@testable import SwivelCore

// M6 review F1: an audio output that drops channels or resamples is partial, so trash keeps the original.
// Measured: WAV clamps to 2 ch and 192 kHz; the M4A preset downmixes 6 ch to 2 and resamples 96 kHz and up to 48 kHz.
@Test(arguments: [
    (AVTarget.wav, 48_000.0, AVAudioChannelCount(2), true), (.m4a, 48_000, 2, true), (.wav, 96_000, 2, true),
    (.wav, 48_000, 6, false), (.m4a, 48_000, 6, false), (.m4a, 96_000, 2, false), (.wav, 384_000, 2, false),
])
func audioOutputCompleteOnlyWhenNothingDropped(target: AVTarget, rate: Double, channels: AVAudioChannelCount, expected: Bool) async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    var url = dir.appendingPathComponent("tone.caf")
    try tone(url, rate: min(rate, 192_000), channels: channels, settings: [
        AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
    ])
    if rate > 192_000 {  // AVAudioFile caps at 192 kHz; afconvert writes past it.
        let hi = dir.appendingPathComponent("hi.caf")
        let run = try Process.run(URL(fileURLWithPath: "/usr/bin/afconvert"), arguments: ["-f", "caff", "-d", "LEI16@\(Int(rate))", url.path, hi.path])
        run.waitUntilExit()
        try FileManager.default.removeItem(at: url)
        url = hi
    }
    #expect(await Converter.probe(url).audioRate == rate)
    let outcome = await Converter.convertAV(url, to: target)
    guard case .converted(_, let outputs, let complete) = outcome, let out = outputs.first else { Issue.record("\(outcome)"); return }
    let a = try await wavFormatOf(out)
    #expect(complete == expected, "\(target) \(rate) Hz \(channels) ch -> \(a.mSampleRate) Hz \(a.mChannelsPerFrame) ch")
}

// M6 review F4: any AV output that drops an audio track, channels, rate or a video track is partial.
private func probe(video: Int = 1, _ audio: [(rate: Double, channels: UInt32)]) -> AVProbe {
    var p = AVProbe()
    (p.videoTracks, p.audioTracks) = (video, audio)
    return p
}

@Test func keepsTracksComparesEveryTrack() {
    let stereo = (rate: 48_000.0, channels: UInt32(2)), six = (rate: 48_000.0, channels: UInt32(6))
    #expect(keepsTracks(probe([stereo]), probe([stereo]), video: true))
    #expect(keepsTracks(probe([stereo, stereo]), probe([stereo, stereo]), video: true))
    #expect(keepsTracks(probe(video: 0, []), probe(video: 0, []), video: false))
    #expect(!keepsTracks(probe([stereo, stereo]), probe([stereo]), video: true))
    #expect(!keepsTracks(probe([six]), probe([stereo]), video: true))
    #expect(!keepsTracks(probe([stereo, six]), probe([stereo, stereo]), video: true))
    #expect(!keepsTracks(probe([(96_000, 2)]), probe([stereo]), video: true))
    #expect(!keepsTracks(probe(video: 2, [stereo]), probe([stereo]), video: true))
    #expect(!keepsTracks(probe([stereo]), probe([]), video: true))
    // An audio target drops video by design.
    #expect(keepsTracks(probe([stereo]), probe(video: 0, [stereo]), video: false))
}

// Measured: the MP4 and HEVC routes keep every audio track and 5.1, from AAC or LPCM, on passthrough and encode.
@Test(arguments: [
    (AVFixture.Video.h264, 1, 2, false, AVTarget.mp4), (.hevc, 1, 2, false, .mp4), (.hevc, 1, 2, false, .hevc),
    (.h264, 2, 1, false, .mp4), (.h264, 1, 6, false, .mp4), (.hevc, 1, 6, false, .mp4),
    (.h264, 2, 1, true, .mp4), (.h264, 1, 6, true, .mp4), (.h264, 2, 1, true, .hevc),
])
func videoOutputThatKeepsEveryTrackIsComplete(video: AVFixture.Video, tracks: Int, channels: Int, pcm: Bool, target: AVTarget) async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let src = try await AVFixture.write("clip.mov", in: dir, video: video, audioTracks: tracks, channels: channels, pcm: pcm)
    let outcome = await Converter.convertAV(src, to: target)
    guard case .converted(_, let outputs, let complete) = outcome, let out = outputs.first else { Issue.record("\(outcome)"); return }
    let audio = try await AVURLAsset(url: out).loadTracks(withMediaType: .audio)
    #expect(audio.count == tracks)
    #expect(complete)
}

// An audio-only file with two tracks is mixed into one, so WAV and M4A are partial.
@Test(arguments: [AVTarget.wav, .m4a], [(2, 1, false), (1, 2, true)])
func audioOnlyTracks(target: AVTarget, src: (tracks: Int, channels: Int, complete: Bool)) async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let url = try await AVFixture.write("tracks.mov", in: dir, video: nil, audioTracks: src.tracks, channels: src.channels, pcm: true)
    let outcome = await Converter.convertAV(url, to: target)
    guard case .converted(_, _, let complete) = outcome else { Issue.record("\(outcome)"); return }
    #expect(complete == src.complete)
}
