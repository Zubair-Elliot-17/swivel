import Foundation
import Testing
import UniformTypeIdentifiers
import SwivelCore

@Test(arguments: [("PNG", ImageFormat.png), ("JPEG", .jpeg), ("HEIC", .heic), ("WebP", .webp), ("TIFF", .tiff)])
func sliceNameMapsToFormat(name: String, format: ImageFormat) {
    #expect(ImageFormat(rawValue: name) == format)
}

@Test func pdfSliceIsNotAnImageFormat() {
    #expect(ImageFormat(rawValue: "PDF") == nil)
    #expect(Geometry.sliceNames.compactMap(ImageFormat.init(rawValue:)) == ImageFormat.allCases)
}

@Test(arguments: [(ImageFormat.png, "png"), (.jpeg, "jpg"), (.heic, "heic"), (.webp, "webp"), (.tiff, "tiff")])
func fileExtensions(format: ImageFormat, ext: String) {
    #expect(format.fileExtension == ext)
}

@Test(arguments: [
    ("/Users/me/Pictures/photo.png", 1, "/Users/me/Pictures/photo.jpg"),
    ("/Users/me/Pictures/photo.png", 2, "/Users/me/Pictures/photo 2.jpg"),
    ("/Users/me/Pictures/photo.png", 10, "/Users/me/Pictures/photo 10.jpg"),
    ("/Users/me/a.b.png", 1, "/Users/me/a.b.jpg"),
    ("/Users/me/.hidden", 1, "/Users/me/.hidden.jpg"),
    ("/Users/me/README", 1, "/Users/me/README.jpg"),
    ("/Users/me/photo 2.png", 1, "/Users/me/photo 2.jpg"),
    ("/Users/me/photo 2.png", 2, "/Users/me/photo 2 2.jpg"),
    ("/Volumes/Card/DCIM/IMG_1.HEIC", 1, "/Volumes/Card/DCIM/IMG_1.jpg"),
])
func outputNames(source: String, attempt: Int, expected: String) {
    #expect(OutputName.candidate(for: URL(fileURLWithPath: source), ext: "jpg", attempt: attempt).path == expected)
}

@Test(arguments: [
    (UTType?.none, 1, ImageFormat.png, SkipReason?.some(.notImage)),
    (UTType.pdf, 1, .png, .notImage),
    (UTType.folder, 1, .png, .notImage),
    (UTType.plainText, 1, .png, .notImage),
    (UTType.png, 0, .jpeg, .notImage),
    (UTType.jpeg, 1, .jpeg, .already(.jpeg)),
    (UTType.png, 1, .png, .already(.png)),
    (UTType.heic, 1, .jpeg, nil),
    (UTType.png, 1, .webp, nil),
])
func skipRules(type: UTType?, count: Int, target: ImageFormat, expected: SkipReason?) {
    #expect(skipReason(sourceType: type, imageCount: count, target: target) == expected)
}

@Test(arguments: [(SkipReason.notImage, "not an image"), (.already(.png), "already PNG"), (.already(.webp), "already WebP"), (.unreadable, "can't read")])
func skipReasonText(reason: SkipReason, text: String) {
    #expect(reason.description == text)
}
