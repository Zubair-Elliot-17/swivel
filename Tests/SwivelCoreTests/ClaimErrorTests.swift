import Foundation
import Testing
import SwivelCore

// A non-collision write error must surface as-is, not be retried into "no free file name".
@Test func readOnlyFolderReportsTheWriteError() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("swivel-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
        try? FileManager.default.removeItem(at: dir)
    }
    let source = try write(.png, in: dir)
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
    guard case .failed(_, let reason, _) = await Converter.convert(source, to: .jpeg) else {
        Issue.record("expected failure"); return
    }
    #expect(reason != "no free file name")
    #expect(reason == "no permission")
}
