import Foundation
import XCTest
@testable import BetterVoiceCore

final class SavedSessionHistoryTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BetterVoiceHistoryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testExtractsTheTranscriptFromSessionMarkdown() {
        XCTAssertEqual(
            SavedSessionHistory.transcript(fromMarkdown: "# BetterVoice session\n\nMove this button left.\n"),
            "Move this button left."
        )
        XCTAssertEqual(
            SavedSessionHistory.transcript(
                fromMarkdown: "# BetterVoice session\n\nMove this button.\n\n## Screen context\n\n![Context 1](context-1.png)\n\n"
            ),
            "Move this button."
        )
        XCTAssertEqual(
            SavedSessionHistory.transcript(
                fromMarkdown: "# BetterVoice session\n\n_No transcript captured._\n\n## Screen context\n\n![Context 1](context-1.png)\n\n"
            ),
            ""
        )
    }

    func testReadsTheRecordingTimeFromAGeneratedFolderName() {
        let date = SavedSessionHistory.recordedAt(
            folderName: "2026-08-23T15-16-45Z-C81A6E98-FD94-4FC6-AF2C-8928EBD938B1"
        )
        XCTAssertEqual(date, ISO8601DateFormatter().date(from: "2026-08-23T15:16:45Z"))
        XCTAssertNil(SavedSessionHistory.recordedAt(folderName: "my-important-folder"))
    }

    func testLoadsSessionsNewestFirstWithImagesInCaptureOrder() throws {
        let older = try makeSession(
            "2026-08-22T09-00-00Z-C81A6E98-FD94-4FC6-AF2C-8928EBD938B1",
            markdown: "# BetterVoice session\n\nOlder note.\n"
        )
        let newer = try makeSession(
            "2026-08-23T15-16-45Z-D81A6E98-FD94-4FC6-AF2C-8928EBD938B1",
            markdown: "# BetterVoice session\n\nNewer note.\n\n## Screen context\n\n",
            files: ["context-10.png", "context-2.png", "notes.txt"]
        )
        _ = try makeSession(
            "2026-08-23T16-00-00Z-E81A6E98-FD94-4FC6-AF2C-8928EBD938B1",
            markdown: "# BetterVoice session\n\n_No transcript captured._\n"
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("my-important-folder"),
            withIntermediateDirectories: true
        )

        let sessions = SavedSessionHistory.load(from: root)

        XCTAssertEqual(sessions.map(\.id), [newer.lastPathComponent, older.lastPathComponent])
        XCTAssertEqual(sessions.map(\.transcript), ["Newer note.", "Older note."])
        XCTAssertEqual(sessions[0].images.map(\.lastPathComponent), ["context-2.png", "context-10.png"])
        XCTAssertEqual(SavedSessionHistory.load(from: root, limit: 1).map(\.transcript), ["Newer note."])
    }

    func testReturnsNothingWhenTheFolderIsMissing() {
        XCTAssertEqual(SavedSessionHistory.load(from: root.appendingPathComponent("missing")), [])
    }

    private func makeSession(_ name: String, markdown: String, files: [String] = []) throws -> URL {
        let folder = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try markdown.write(to: folder.appendingPathComponent("context.md"), atomically: true, encoding: .utf8)
        for file in files {
            try Data([0]).write(to: folder.appendingPathComponent(file))
        }
        return folder
    }
}
