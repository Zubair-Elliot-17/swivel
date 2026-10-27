import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Vision

extension Converter {
    /// `<stem>.txt` from an image (OCR of the primary frame) or a PDF (text layer per page, else OCR at 300 dpi
    /// within `maxPixels` rendered in all).
    public static func extractText(_ source: URL, maxPages: Int = 100, maxPixels: Int = pixelBudget) async -> Outcome {
        let text: String
        do {
            if isPDF(source) {
                let doc: PDFDocument
                switch openPDF(source) {
                case .success(let opened): doc = opened
                case .failure(let failure): return failure.outcome
                }
                if doc.pageCount > maxPages {
                    log.info("\(source.lastPathComponent, privacy: .public): \(pagesSkipped(doc.pageCount - maxPages, max: maxPages), privacy: .public)")
                }
                var pages: [String] = [], spent = 0
                for i in 0..<min(doc.pageCount, maxPages) {
                    guard let page = doc.page(at: i) else { throw ConvertError("couldn't read PDF") }
                    var pageText = page.string ?? ""
                    if !hasText(pageText) {
                        guard spend(&spent, try renderSize(page, dpi: 300), max: maxPixels) else {
                            logBudget(source, skipped: min(doc.pageCount, maxPages) - i, max: maxPixels)
                            break
                        }
                        pageText = try recognize(try render(page, dpi: 300), orientation: .up)
                    }
                    pages.append(pageText.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                text = pages.filter { !$0.isEmpty }.joined(separator: "\n\n")
            } else {
                let src = CGImageSourceCreateWithURL(source as CFURL, nil)
                let type = src.flatMap(CGImageSourceGetType).flatMap { UTType($0 as String) }
                guard let src, let type, type.conforms(to: .image), CGImageSourceGetCount(src) > 0 else {
                    return skipped(source, .notImage)
                }
                // Q5: primary frame only, as M2 encode does.
                let index = CGImageSourceGetPrimaryImageIndex(src)
                _ = try pixelSize(src, at: index)
                guard let image = CGImageSourceCreateImageAtIndex(src, index, nil) else { throw ConvertError("couldn't read image") }
                let props = CGImageSourceCopyPropertiesAtIndex(src, index, nil) as? [CFString: Any]
                let orientation = (props?[kCGImagePropertyOrientation] as? UInt32).flatMap(CGImagePropertyOrientation.init) ?? .up
                text = try recognize(image, orientation: orientation)
            }
            guard hasText(text) else { return .skipped(source: source, .noText) }
            return .converted(source: source, outputs: [try claim(Data(text.utf8), source: source, ext: "txt")])
        } catch {
            return failed(source, error)
        }
    }

    /// `extractText` for each URL, 4 at a time like `convertBatch`; keeps input order.
    public static func textBatch(_ urls: [URL], maxInFlight: Int = 4) async -> [Outcome] {
        await window(urls, maxInFlight: maxInFlight) { await extractText($0) }
    }

    private static func hasText(_ text: String) -> Bool {
        text.contains { !$0.isWhitespace }
    }

    /// Vision OCR, one line per observation; the request never leaves this call (not Sendable).
    private static func recognize(_ image: CGImage, orientation: CGImagePropertyOrientation) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.revision = VNRecognizeTextRequestRevision3
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: image, orientation: orientation).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
}
