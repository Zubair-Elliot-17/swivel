import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import os

/// Page size and CTM that draw a `width` x `height` image (in `(0,0,w,h)`) upright for EXIF `orientation` 1-8.
/// Rotating the drawing, not the pixels, keeps JPEG bytes passed through.
public func orientedPage(orientation: Int, width: Int, height: Int) -> (size: CGSize, transform: CGAffineTransform) {
    let w = CGFloat(width), h = CGFloat(height)
    let upright = CGSize(width: w, height: h), turned = CGSize(width: h, height: w)
    switch orientation {
    case 2: return (upright, CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: w, ty: 0))
    case 3: return (upright, CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: w, ty: h))
    case 4: return (upright, CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: h))
    case 5: return (turned, CGAffineTransform(a: 0, b: -1, c: -1, d: 0, tx: h, ty: w))
    case 6: return (turned, CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: w))
    case 7: return (turned, CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0))
    case 8: return (turned, CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: h, ty: 0))
    default: return (upright, .identity)
    }
}

let log = Logger(subsystem: "dev.zubair.swivel", category: "convert")

/// Log note for pages dropped by a cap, e.g. "1 page skipped (max 100)" or "2 pages skipped (max 2000 MP)".
func pagesSkipped(_ count: Int, max: Int, unit: String = "") -> String {
    "\(count) page\(count == 1 ? "" : "s") skipped (max \(max)\(unit))"
}

extension Converter {
    /// Draws every frame of the image sources, in drop order, into one PDF named after the first converted one.
    /// One job: frames are decoded one at a time, so only one bitmap is alive.
    public static func makePDF(_ urls: [URL], maxPages: Int = 500) async -> [Outcome] {
        // Streams to a hidden temp file next to the first source that gives a page, so the PDF never sits in memory.
        var ctx: CGContext?, temp: URL?
        defer { if let temp { try? FileManager.default.removeItem(at: temp) } }
        func context(near url: URL) throws -> CGContext {
            if let ctx { return ctx }
            let file = url.deletingLastPathComponent().appendingPathComponent(".swivel-\(UUID().uuidString).pdf")
            // Creating it first surfaces the write error (no permission, read-only) that CGContext would hide.
            try Data().write(to: file, options: .withoutOverwriting)
            temp = file
            guard let made = CGContext(file as CFURL, mediaBox: nil, nil) else { throw ConvertError("couldn't write PDF") }
            ctx = made
            return made
        }
        // nil marks a source that gave pages; it becomes .converted once the PDF is claimed.
        var outcomes: [Outcome?] = [], pages = 0
        for url in urls {
            if isPDF(url) {
                outcomes.append(.skipped(source: url, .alreadyPDF))
                continue
            }
            let src = CGImageSourceCreateWithURL(url as CFURL, nil)
            let type = src.flatMap(CGImageSourceGetType).flatMap { UTType($0 as String) }
            guard let src, let type, type.conforms(to: .image), CGImageSourceGetCount(src) > 0 else {
                outcomes.append(skipped(url, .notImage))
                continue
            }
            let count = CGImageSourceGetCount(src), room = maxPages - pages
            do {
                for i in 0..<count { _ = try pixelSize(src, at: i) }
                if count > room { log.info("\(url.lastPathComponent, privacy: .public): \(pagesSkipped(count - max(room, 0), max: maxPages), privacy: .public)") }
                guard room > 0 else {
                    outcomes.append(.skipped(source: url, .pageLimit))
                    continue
                }
                // Q1: HEIC/WebP decode to huge Flate pages, so they go in as JPEG q0.85; JPEG bytes pass through as-is.
                let lossy = [UTType.heic, .heif, .webP].contains { type.conforms(to: $0) }
                for i in 0..<min(count, room) {
                    guard let frame = CGImageSourceCreateImageAtIndex(src, i, nil) else { throw ConvertError("couldn't read image") }
                    let image = lossy && !hasAlpha(frame) ? jpegBacked(frame) ?? frame : frame
                    let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any]
                    let page = orientedPage(
                        orientation: props?[kCGImagePropertyOrientation] as? Int ?? 1, width: image.width, height: image.height)
                    var box = CGRect(origin: .zero, size: page.size)
                    let ctx = try context(near: url)
                    // Each page gets its own media box; nil would reuse the context's default.
                    ctx.beginPDFPage([kCGPDFContextMediaBox: Data(bytes: &box, count: MemoryLayout<CGRect>.size)] as CFDictionary)
                    ctx.concatenate(page.transform)
                    ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                    ctx.endPDFPage()
                    pages += 1
                }
                outcomes.append(nil)
            } catch {
                outcomes.append(failed(url, error))
            }
        }
        ctx?.closePDF()
        ctx = nil  // releasing the context flushes the file
        guard let temp, let first = outcomes.firstIndex(where: { $0 == nil }) else { return outcomes.map { $0! } }
        do {
            // CGDataConsumer drops write errors (disk full), so check the file before naming it.
            guard CGPDFDocument(temp as CFURL)?.numberOfPages == pages else { throw ConvertError("couldn't write PDF") }
            let output = try claim(file: temp, source: urls[first], ext: "pdf")
            return zip(urls, outcomes).map { $1 ?? .converted(source: $0, outputs: [output]) }
        } catch {
            return zip(urls, outcomes).map { $1 ?? failed($0, error) }
        }
    }

    static func isPDF(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType?.conforms(to: .pdf) == true
    }

    /// JPEG can't keep alpha (ImageIO flattens HEIC on black), so frames with alpha stay lossless.
    private static func hasAlpha(_ image: CGImage) -> Bool {
        ![.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
    }

    /// The frame re-encoded as JPEG q0.85 through the M2 encoder, so CG embeds the JPEG bytes.
    private static func jpegBacked(_ frame: CGImage) -> CGImage? {
        guard let data = try? encode(frame, to: .jpeg), let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }
}
