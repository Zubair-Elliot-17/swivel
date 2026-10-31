import AVFoundation
import CoreMedia
import Foundation
import UniformTypeIdentifiers

/// Audio/video targets on the wheel; raw values are the slice names.
public enum AVTarget: String, CaseIterable, Sendable {
    case mp4 = "MP4", hevc = "HEVC", mov = "MOV", gif = "GIF", m4a = "M4A", wav = "WAV"

    /// HEVC goes in an MP4 container, as Permute does.
    public var fileExtension: String {
        switch self {
        case .mp4, .hevc: "mp4"
        case .mov: "mov"
        case .gif: "gif"
        case .m4a: "m4a"
        case .wav: "wav"
        }
    }

    public var needsVideo: Bool { self != .m4a && self != .wav }
}

/// What a probe read from a file, as plain values; numbers are raw and unchecked until `avDecision`.
public struct AVProbe: Sendable {
    public var contentType: UTType?
    public var opened = false
    /// AVFoundation error code when the asset failed to load.
    public var errorCode: Int?
    public var playable = false, protected = false
    /// Raw `CMTime.seconds`: may be NaN, infinite, negative or huge.
    public var duration = Double.nan
    /// Raw seconds of the first video track's time range; a GIF covers only that span.
    public var videoStart = Double.nan, videoDuration = Double.nan
    public var hasVideo = false, hasAudio = false
    public var videoCodec: FourCharCode?, audioCodec: FourCharCode?
    /// Natural size after the preferred transform, so a side can be negative.
    public var videoSize = CGSize.zero
    public var audioRate = 0.0
    public var audioChannels: UInt32 = 0

    public init() {}
}

public enum AVDecision: Equatable, Sendable {
    case skip(SkipReason)
    case fail(String)
    /// Try Passthrough first, then the target's encode preset.
    case remux
    case encode
}

let gifMaxSeconds = 30.0

/// Pure: every hostile-value check, in the order open, DRM, tracks, playable, duration, size, already, caps.
public func avDecision(_ p: AVProbe, _ t: AVTarget) -> AVDecision {
    let missing: SkipReason = t.needsVideo ? .noVideo : .noAudio
    guard p.contentType?.conforms(to: .audiovisualContent) == true else { return .skip(missing) }
    guard p.opened else {
        switch p.errorCode {
        case AVError.contentIsProtected.rawValue, AVError.contentIsNotAuthorized.rawValue: return .skip(.drm)
        case AVError.decoderNotFound.rawValue: return .skip(.codec)
        default: return .skip(.notSupported)
        }
    }
    if p.protected { return .skip(.drm) }
    if t.needsVideo ? !p.hasVideo : !p.hasAudio { return .skip(missing) }
    if !p.playable { return .skip(.codec) }
    guard p.duration.isFinite, p.duration > 0 else { return .skip(.notSupported) }
    if t.needsVideo {
        let w = abs(p.videoSize.width), h = abs(p.videoSize.height)
        guard w.isFinite, h.isFinite, w > 0, h > 0 else { return .skip(.codec) }
    }
    let type = p.contentType!, avc1 = p.videoCodec == fourCC("avc1"), hvc1 = p.videoCodec == fourCC("hvc1")
    let aac = p.audioCodec == kAudioFormatMPEG4AAC
    switch t {
    case .mp4:
        if type.conforms(to: .mpeg4Movie) && avc1 { return .skip(.alreadyAV(.mp4)) }
        return avc1 ? .remux : .encode
    case .hevc:
        if type.conforms(to: .mpeg4Movie) && hvc1 { return .skip(.alreadyAV(.hevc)) }
        return hvc1 ? .remux : .encode
    case .mov:
        return type.conforms(to: .quickTimeMovie) ? .skip(.alreadyAV(.mov)) : .remux
    case .m4a:
        if type.conforms(to: .mpeg4Audio) && aac && !p.hasVideo { return .skip(.alreadyAV(.m4a)) }
        return aac ? .remux : .encode
    case .gif:
        guard p.videoStart.isFinite, p.videoStart >= 0, p.videoDuration.isFinite, p.videoDuration > 0 else { return .skip(.notSupported) }
        return p.videoDuration > gifMaxSeconds ? .fail("too long for GIF (max 30 s)") : .encode
    case .wav:
        if type.conforms(to: .wav) { return .skip(.alreadyAV(.wav)) }
        let f = wavFormat(rate: p.audioRate, channels: p.audioChannels)
        return wavTooLarge(duration: p.duration, rate: f.rate, channels: f.channels) ? .fail("too long for WAV (4 GB limit)") : .encode
    }
}

/// WAV output rate and channels from the file's values: a bad rate becomes 44.1 kHz, channels 1...2.
/// AVFoundation raises an uncatchable exception for rates outside 8...192 kHz, so those clamp.
func wavFormat(rate: Double, channels: UInt32) -> (rate: Double, channels: Int) {
    (rate.isFinite && rate > 0 ? min(max(rate, 8_000), 192_000) : 44_100, Int(clamping: min(max(channels, 1), 2)))
}

/// RIFF sizes are 32-bit, so 16-bit PCM at or over 4 GiB can't be written; computed in Double.
func wavTooLarge(duration: Double, rate: Double, channels: Int) -> Bool {
    duration * rate * Double(channels) * 2 >= 4 * 1024 * 1024 * 1024
}

private func fourCC(_ s: String) -> FourCharCode { s.utf8.reduce(0) { $0 << 8 | FourCharCode($1) } }

extension Converter {
    /// Converts one audio/video file; never throws. `progress` gets 0...1 from any thread.
    public static func convertAV(
        _ source: URL, to target: AVTarget, progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async -> Outcome {
        if Task.isCancelled { return .failed(source: source, reason: "cancelled") }
        let p = await probe(source), remux: Bool
        // A load cut short by the cancel would read as "not supported".
        if Task.isCancelled { return .failed(source: source, reason: "cancelled") }
        switch avDecision(p, target) {
        case .skip(let reason): return skipped(source, reason)
        case .fail(let reason): return .failed(source: source, reason: reason)
        case .remux: remux = true
        case .encode: remux = false
        }
        do {
            let made: URL? = switch target {
            case .wav: try await viaTemp(near: source, ext: "wav") { try await writeWAV(source, to: $0, probe: p, progress: progress) }
            case .gif: try claim(await makeGIF(source, probe: p, progress: progress), source: source, ext: "gif")
            default: try await export(source, to: target, remux: remux, progress: progress)
            }
            guard let output = made else { return skipped(source, .codec) }
            return .converted(source: source, outputs: [output])
        } catch {
            // Export may surface a cancel as its own error, so the task's state decides.
            if Task.isCancelled || error is CancellationError { return .failed(source: source, reason: "cancelled") }
            return failed(source, error)
        }
    }

    /// `convertAV` for each URL, one at a time (parallel exports share one media engine); keeps input order.
    public static func avBatch(
        _ urls: [URL], to target: AVTarget, progress: @escaping @Sendable (URL, Double) -> Void = { _, _ in }
    ) async -> [Outcome] {
        await window(urls, maxInFlight: 1) { url in await convertAV(url, to: target) { progress(url, $0) } }
    }

    /// Fixed (preset, file type) routes, tried in order; every file type must be in the session's supportedFileTypes.
    static func routes(_ target: AVTarget, remux: Bool) -> [(preset: String, fileType: AVFileType)] {
        let (encode, type): (String, AVFileType)
        switch target {
        case .mp4: (encode, type) = (AVAssetExportPresetHighestQuality, .mp4)
        case .hevc: (encode, type) = (AVAssetExportPresetHEVCHighestQuality, .mp4)
        case .mov: (encode, type) = (AVAssetExportPresetHighestQuality, .mov)
        case .m4a: (encode, type) = (AVAssetExportPresetAppleM4A, .m4a)
        case .gif, .wav: return []
        }
        return (remux ? [(AVAssetExportPresetPassthrough, type)] : []) + [(encode, type)]
    }

    /// Exports through the first compatible route, or returns nil when none is (never calling export).
    private static func export(
        _ source: URL, to target: AVTarget, remux: Bool, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL? {
        let asset = AVURLAsset(url: source)
        for route in routes(target, remux: remux) {
            // A file type outside supportedFileTypes raises an ObjC exception, which Swift can't catch.
            guard let session = AVAssetExportSession(asset: asset, presetName: route.preset),
                  session.supportedFileTypes.contains(route.fileType),
                  await AVAssetExportSession.compatibility(ofExportPreset: route.preset, with: asset, outputFileType: route.fileType)
            else { continue }
            return try await viaTemp(near: source, ext: target.fileExtension) { temp in
                try await run(session, to: temp, as: route.fileType, progress: progress)
            }
        }
        return nil
    }

    private static func run(
        _ s: AVAssetExportSession, to url: URL, as type: AVFileType, progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        // shortcut: other tasks only read `progress`/`status` and call cancelExport on the non-Sendable session;
        // use states(updateInterval:) at a macOS 15 target.
        nonisolated(unsafe) let session = s
        // Never cancelled itself: export(to:as:) in a cancelled task can call exportAsynchronously twice, an ObjC exception.
        let job = Task { try await session.export(to: url, as: type) }
        let poll = Task {
            while !Task.isCancelled {
                progress(Double(session.progress))
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
        defer { poll.cancel() }
        try await withTaskCancellationHandler {
            try await job.value
        } onCancel: {
            Task {
                // cancelExport before the session starts leaves it cancelled before export runs; wait (max 10 s) for it.
                for _ in 0..<1000 where session.status == .unknown || session.status == .waiting { await pause(10) }
                // Still not started: cancelling now raises the same exception; the export runs out and viaTemp drops it.
                guard session.status != .unknown else { convertLog.error("export never started; not cancelled"); return }
                session.cancelExport()
            }
        }
        poll.cancel()
        await poll.value  // so no late poll value lands after the final 1
        progress(1)
    }

    /// Runs `write` into a hidden `.swivel-<UUID>/` folder next to the source, then claims a Keep Both name.
    static func viaTemp(near source: URL, ext: String, write: (URL) async throws -> Void) async throws -> URL {
        let dir = source.deletingLastPathComponent().appendingPathComponent(".swivel-\(UUID().uuidString)")
        // Creating it first surfaces no permission / read-only before any work.
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
        do {
            let temp = dir.appendingPathComponent("output.\(ext)")
            try await write(temp)
            try Task.checkCancellation()
            let output = try claim(file: temp, source: source, ext: ext)
            try? FileManager.default.removeItem(at: dir)
            return output
        } catch {
            await removeLate(dir)
            throw error
        }
    }

    /// A cancelled export can still create its file ~100 ms after returning, which can make the removal fail
    /// (not empty); retry. Once the folder is gone a late write has nowhere to land.
    private static func removeLate(_ dir: URL) async {
        for _ in 0..<20 {
            if (try? FileManager.default.removeItem(at: dir)) != nil || !FileManager.default.fileExists(atPath: dir.path) { return }
            await pause(100)
        }
        convertLog.error("couldn't remove \(dir.path, privacy: .public)")
    }

    /// Sleeps even in a cancelled task (Task.sleep returns at once there).
    private static func pause(_ ms: Int) async {
        await withCheckedContinuation { done in DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(ms)) { done.resume() } }
    }

    /// Reads what `avDecision` needs; never throws. Non-AV files return before any AVAsset is made.
    static func probe(_ url: URL) async -> AVProbe {
        var p = AVProbe()
        p.contentType = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
            ?? UTType(filenameExtension: url.pathExtension)
        guard p.contentType?.conforms(to: .audiovisualContent) == true else { return p }
        let asset = AVURLAsset(url: url)
        do {
            let (playable, protected, duration) = try await asset.load(.isPlayable, .hasProtectedContent, .duration)
            (p.playable, p.protected, p.duration) = (playable, protected, duration.seconds)
            if let video = try await asset.loadTracks(withMediaType: .video).first {
                p.hasVideo = true
                let (size, transform, formats, range) = try await video.load(.naturalSize, .preferredTransform, .formatDescriptions, .timeRange)
                p.videoSize = size.applying(transform)
                (p.videoStart, p.videoDuration) = (range.start.seconds, range.duration.seconds)
                p.videoCodec = formats.first.map(CMFormatDescriptionGetMediaSubType)
            }
            if let audio = try await asset.loadTracks(withMediaType: .audio).first {
                p.hasAudio = true
                if let format = try await audio.load(.formatDescriptions).first {
                    p.audioCodec = CMFormatDescriptionGetMediaSubType(format)
                    if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee {
                        (p.audioRate, p.audioChannels) = (asbd.mSampleRate, asbd.mChannelsPerFrame)
                    }
                }
            }
            p.opened = true
        } catch {
            let ns = error as NSError
            p.errorCode = ns.domain == AVFoundationErrorDomain ? ns.code : nil
        }
        return p
    }
}
