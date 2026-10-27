import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import SwivelCore

// Regression tests for the M3 review fix round.

/// A one-page PDF written by hand, so the media box can hold values CGContext would refuse.
private func rawPDF(mediaBox: String, in dir: URL, name: String = "raw") throws -> URL {
    var out = "%PDF-1.4\n", offsets: [Int] = []
    let objects = [
        "<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [\(mediaBox)] >>",
    ]
    for (i, object) in objects.enumerated() {
        offsets.append(out.utf8.count)
        out += "\(i + 1) 0 obj\n\(object)\nendobj\n"
    }
    let xref = out.utf8.count
    out += "xref\n0 4\n0000000000 65535 f \n" + offsets.map { String(format: "%010d 00000 n \n", $0) }.joined()
    out += "trailer\n<< /Size 4 /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
    let url = dir.appendingPathComponent("\(name).pdf")
    try Data(out.utf8).write(to: url)
    return url
}

// MARK: F1 crafted page boxes

private let hostileBoxes = ["0 0 100000000000000000000 0.00000000001", "0 0 100000000000000000000 1", "0 0 0.5 0.5"]

@Test(arguments: hostileBoxes)
func hostilePageBoxFailsForImages(box: String) async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let source = try rawPDF(mediaBox: box, in: dir)
    #expect(await Converter.convert(source, to: .png) == .failed(source: source, reason: "couldn't read PDF"))
    #expect(try files(in: dir) == ["raw.pdf"])
}

@Test(arguments: hostileBoxes)
func hostilePageBoxFailsForText(box: String) async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let source = try rawPDF(mediaBox: box, in: dir)
    #expect(await Converter.extractText(source) == .failed(source: source, reason: "couldn't read PDF"))
    #expect(try files(in: dir) == ["raw.pdf"])
}

@Test func longThinPageIsClampedPerSide() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let source = try rawPDF(mediaBox: "0 0 40000 10", in: dir)
    guard case .converted(_, let outputs) = await Converter.convert(source, to: .png) else { Issue.record("not converted"); return }
    let out = try ReadBack(outputs[0])
    #expect(out.width == 65535 && (1...21).contains(out.height), "\(out.width)x\(out.height)")
}
