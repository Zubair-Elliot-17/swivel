import Foundation
import UniformTypeIdentifiers

/// Which sources may go to the Trash after a batch; pure, the app does the moving.
public enum Trash {
    /// Fully converted sources with outputs, de-duplicated by standardized path in first-seen order.
    /// Extractions (Text, GIF, and M4A/WAV from a video source) keep their original.
    public static func trashCandidates(
        _ outcomes: [Outcome], slice: String, isVideo: (URL) async -> Bool
    ) async -> [(source: URL, outputs: [URL])] {
        let audio = slice == AVTarget.m4a.rawValue || slice == AVTarget.wav.rawValue
        let conversion = ImageFormat(rawValue: slice) != nil || slice == "PDF" || audio
            || [AVTarget.mp4, .hevc, .mov].contains { $0.rawValue == slice }
        guard conversion else { return [] }
        var seen: Set<String> = [], picked: [(source: URL, outputs: [URL])] = []
        for case .converted(let source, let outputs, true) in outcomes where !outputs.isEmpty {
            let path = source.standardizedFileURL.path
            guard !outputs.contains(where: { $0.standardizedFileURL.path == path }), !seen.contains(path) else { continue }
            if audio, await isVideo(source) { continue }
            seen.insert(path)
            picked.append((source, outputs))
        }
        return picked
    }

    /// A `.movie` type or any video track; extracting audio from such a file keeps it.
    public static func hasVideo(_ url: URL) async -> Bool {
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType ?? UTType(filenameExtension: url.pathExtension)
        if type?.conforms(to: .movie) == true { return true }
        return await Converter.probe(url).hasVideo
    }
}
