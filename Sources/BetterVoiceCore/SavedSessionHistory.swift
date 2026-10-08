import Foundation

/// One saved recording as listed in History.
public struct SavedSession: Identifiable, Equatable, Sendable {
    public let folder: URL
    public let recordedAt: Date
    public let transcript: String
    public let images: [URL]

    public var id: String { folder.lastPathComponent }

    public init(folder: URL, recordedAt: Date, transcript: String, images: [URL]) {
        self.folder = folder
        self.recordedAt = recordedAt
        self.transcript = transcript
        self.images = images
    }
}

public enum SavedSessionHistory {
    public static let maxMarkdownBytes = 256 * 1_024

    /// The spoken part of a session's `context.md`, without the heading or image list.
    public static func transcript(fromMarkdown markdown: String) -> String {
        markdown
            .replacingOccurrences(of: "# BetterVoice session\n\n", with: "")
            .components(separatedBy: "\n\n## Screen context")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_No transcript captured._", with: "") ?? ""
    }

    /// The recording time encoded in a generated session folder name.
    public static func recordedAt(folderName: String) -> Date? {
        guard isBetterVoiceSessionName(folderName) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss'Z'"
        return formatter.date(from: String(folderName.prefix(20)))
    }

    /// Saved sessions under `root`, newest first. Sessions with neither a
    /// transcript nor an image are skipped, as are symlinks and oversized files.
    public static func load(from root: URL, limit: Int = 200) -> [SavedSession] {
        let manager = FileManager.default
        guard let folders = try? manager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let candidates = folders.compactMap { folder -> (URL, Date)? in
            guard let recordedAt = recordedAt(folderName: folder.lastPathComponent),
                  let values = try? folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true,
                  values.isSymbolicLink != true
            else { return nil }
            return (folder, recordedAt)
        }.sorted { $0.1 > $1.1 }

        var sessions: [SavedSession] = []
        for (folder, recordedAt) in candidates {
            guard sessions.count < limit else { break }
            let transcript = transcript(in: folder)
            let images = images(in: folder)
            guard !transcript.isEmpty || !images.isEmpty else { continue }
            sessions.append(SavedSession(
                folder: folder,
                recordedAt: recordedAt,
                transcript: transcript,
                images: images
            ))
        }
        return sessions
    }

    private static func transcript(in folder: URL) -> String {
        let markdownURL = folder.appendingPathComponent("context.md")
        guard let values = try? markdownURL.resourceValues(forKeys: [
            .fileSizeKey,
            .isRegularFileKey,
            .isSymbolicLinkKey
        ]),
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              let fileSize = values.fileSize,
              fileSize <= maxMarkdownBytes,
              let markdown = try? String(contentsOf: markdownURL, encoding: .utf8)
        else { return "" }
        return transcript(fromMarkdown: markdown)
    }

    private static func images(in folder: URL) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return files
            .filter { url in
                guard url.lastPathComponent.hasPrefix("context-"),
                      url.pathExtension.lowercased() == "png",
                      let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                else { return false }
                return values.isRegularFile == true && values.isSymbolicLink != true
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}
