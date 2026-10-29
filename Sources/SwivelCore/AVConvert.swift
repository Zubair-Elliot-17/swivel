import Foundation

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
