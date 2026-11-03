import Foundation
import Testing
@testable import SwivelCore

// M6 gaps: AC5 says an AV export stays complete, so its source can be trashed.

@Test(arguments: [AVTarget.mp4, .wav])
func avExportIsComplete(target: AVTarget) async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let src = try await AVFixture.write("clip.mov", in: dir)
    guard case .converted(_, _, let complete) = await Converter.convertAV(src, to: target) else {
        Issue.record("not converted"); return
    }
    #expect(complete)
}

