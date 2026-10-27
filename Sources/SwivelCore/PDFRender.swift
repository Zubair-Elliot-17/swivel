import CoreGraphics
import Foundation
import PDFKit

extension Converter {
    /// One image per page at 150 dpi, at most `maxPages`. The document never leaves this call (PDFKit isn't Sendable).
    static func renderPDF(_ source: URL, to target: ImageFormat, maxPages: Int = 100) -> Outcome {
        let doc: PDFDocument
        switch openPDF(source) {
        case .success(let opened): doc = opened
        case .failure(let failure): return failure.outcome
        }
        let count = doc.pageCount
        if count > maxPages {
            log.info("\(source.lastPathComponent, privacy: .public): \(pagesSkipped(count - maxPages, max: maxPages), privacy: .public)")
        }
        var outputs: [URL] = []
        for i in 0..<min(count, maxPages) {
            do {
                guard let page = doc.page(at: i) else { throw ConvertError("couldn't read PDF") }
                let data = try encode(try render(page, dpi: 150), to: target)
                let number = String(i + 1)
                let suffix = count == 1 ? "" : " page " + String(repeating: "0", count: String(count).count - number.count) + number
                outputs.append(try claim(data, source: source, ext: target.fileExtension, suffix: suffix))
            } catch {
                guard case .failed(_, let reason, let detail) = failed(source, error), !outputs.isEmpty else { return failed(source, error) }
                // shortcut: pages already written stay on disk (same policy as claim), named here for the log.
                let written = outputs.map(\.lastPathComponent).joined(separator: ", ")
                return .failed(source: source, reason: reason, detail: "\(detail ?? reason); wrote \(written)")
            }
        }
        return .converted(source: source, outputs: outputs)
    }

    /// Opens a PDF, or the outcome for one that won't open: unreadable, locked or unparseable.
    static func openPDF(_ source: URL) -> Result<PDFDocument, OpenFailure> {
        guard let doc = PDFDocument(url: source), doc.pageCount > 0 else {
            let outcome = FileManager.default.isReadableFile(atPath: source.path)
                ? Outcome.failed(source: source, reason: "couldn't read PDF") : .skipped(source: source, .unreadable)
            return .failure(OpenFailure(outcome: outcome))
        }
        // isLocked, not isEncrypted: owner-password-only PDFs open and render.
        return doc.isLocked ? .failure(OpenFailure(outcome: .skipped(source: source, .locked))) : .success(doc)
    }

    struct OpenFailure: Error { let outcome: Outcome }

    /// The page's crop box at `dpi` (clamped to 200 MP), honouring /Rotate, on opaque white sRGB.
    static func render(_ page: PDFPage, dpi: CGFloat) throws -> CGImage {
        var box = page.bounds(for: .cropBox).size
        if page.rotation % 180 != 0 { box = CGSize(width: box.height, height: box.width) }
        let scale = min(dpi / 72, (200_000_000 / (box.width * box.height)).squareRoot())
        let w = Int((box.width * scale).rounded()), h = Int((box.height * scale).rounded())
        guard w > 0, h > 0, let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw ConvertError("couldn't read PDF") }
        // Pages are transparent and JPEG has no alpha, so start from white.
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: CGFloat(w) / box.width, y: CGFloat(h) / box.height)
        page.draw(with: .cropBox, to: ctx)
        guard let image = ctx.makeImage() else { throw ConvertError("couldn't read PDF") }
        return image
    }
}
