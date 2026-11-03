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
