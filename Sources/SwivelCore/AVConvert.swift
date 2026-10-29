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
        return p.duration > gifMaxSeconds ? .fail("too long for GIF (max 30 s)") : .encode
    case .wav:
        if type.conforms(to: .wav) { return .skip(.alreadyAV(.wav)) }
        let f = wavFormat(rate: p.audioRate, channels: p.audioChannels)
        return wavTooLarge(duration: p.duration, rate: f.rate, channels: f.channels) ? .fail("too long for WAV (4 GB limit)") : .encode
    }
}

/// WAV output rate and channels from the file's values: a bad rate becomes 44.1 kHz, channels 1...2.
func wavFormat(rate: Double, channels: UInt32) -> (rate: Double, channels: Int) {
    (rate.isFinite && rate > 0 ? rate : 44_100, Int(clamping: min(max(channels, 1), 2)))
}

/// RIFF sizes are 32-bit, so 16-bit PCM at or over 4 GiB can't be written; computed in Double.
func wavTooLarge(duration: Double, rate: Double, channels: Int) -> Bool {
    duration * rate * Double(channels) * 2 >= 4 * 1024 * 1024 * 1024
}

private func fourCC(_ s: String) -> FourCharCode { s.utf8.reduce(0) { $0 << 8 | FourCharCode($1) } }

extension Converter {
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
                let (size, transform, formats) = try await video.load(.naturalSize, .preferredTransform, .formatDescriptions)
                p.videoSize = size.applying(transform)
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
