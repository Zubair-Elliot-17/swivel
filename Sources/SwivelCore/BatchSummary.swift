import AVFoundation
import Foundation

/// Result of converting one dropped file.
public enum Outcome: Equatable, Sendable {
    /// A PDF source gives one output per page; every source of a combined PDF carries the same output.
    case converted(source: URL, outputs: [URL])
    case skipped(source: URL, SkipReason)
    /// `reason` is short for the menu; `detail` is the full error text for the log when it differs.
    case failed(source: URL, reason: String, detail: String? = nil)
}

/// Short menu text for a failure: common write errors by name, anything else cut to 60 characters.
public func menuReason(for error: Error) -> String {
    if error is CancellationError { return "cancelled" }
    let ns = error as NSError
    switch (ns.domain, ns.code) {
    case (NSCocoaErrorDomain, CocoaError.fileWriteNoPermission.rawValue), (NSPOSIXErrorDomain, Int(EACCES)):
        return "no permission"
    case (NSCocoaErrorDomain, CocoaError.fileWriteOutOfSpace.rawValue), (NSPOSIXErrorDomain, Int(ENOSPC)),
         (AVFoundationErrorDomain, AVError.diskFull.rawValue):
        return "disk full"
    case (NSCocoaErrorDomain, CocoaError.fileWriteVolumeReadOnly.rawValue), (NSPOSIXErrorDomain, Int(EROFS)):
        return "read-only volume"
    default:
        let text = ns.localizedDescription
        return text.count > 60 ? text.prefix(59) + "…" : text
    }
}

/// Menu text while a batch runs, e.g. "Converting clip.mov 42% (2 of 5)"; the fraction is clamped and NaN reads 0%.
public func progressLine(name: String, fraction: Double, index: Int, total: Int) -> String {
    let f = fraction.isNaN ? 0 : min(max(fraction, 0), 1)
    let percent = Int(exactly: (f * 100).rounded(.down)) ?? 0
    return "Converting \(name) \(percent)% (\(index) of \(total))"
}

/// One-line menu text for a batch; names files only, never full paths.
public struct BatchSummary {
    public let outputs: [URL]
    public let converted: Int, skipped: Int, failed: Int
    public let menuLine: String

    public init(_ outcomes: [Outcome]) {
        var outputs: [URL] = [], skips: [SkipReason] = [], failure: (URL, String)?, failed = 0, converted = 0
        for outcome in outcomes {
            switch outcome {
            case .converted(_, let urls):
                converted += 1
                // De-duplicated in first-seen order, so Reveal selects a combined PDF once.
                for url in urls where !outputs.contains(url) { outputs.append(url) }
            case .skipped(_, let reason): skips.append(reason)
            case .failed(let source, let reason, _):
                failed += 1
                if failure == nil { failure = (source, reason) }
            }
        }
        self.outputs = outputs
        self.converted = converted
        skipped = skips.count
        self.failed = failed

        let total = outcomes.count
        let skipNote = skips.isEmpty ? "" : ", \(skips.count) skipped"
        if let (source, reason) = failure {
            menuLine = "Failed: \(source.lastPathComponent): \(reason) (\(converted) of \(total) converted\(skipNote))"
        } else if let last = outputs.last {
            menuLine = "Last: \(last.lastPathComponent) (\(converted) of \(total)\(skipNote))"
        } else if let first = skips.first {
            menuLine = "Skipped \(total) of \(total): \(first)"
        } else {
            menuLine = "Last: none"
        }
    }
}
