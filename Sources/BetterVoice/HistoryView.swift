import AppKit
import BetterVoiceCore
import ImageIO
import SwiftUI

struct HistoryView: View {
    @ObservedObject var model: SetupModel

    private var days: [(day: Date, sessions: [SavedSession])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: model.savedSessions) { calendar.startOfDay(for: $0.recordedAt) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if model.savedSessions.isEmpty {
                emptyState
            } else {
                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(days, id: \.day) { group in
                        VStack(alignment: .leading, spacing: 9) {
                            Text(title(for: group.day))
                                .font(.caption.weight(.semibold))
                                .textCase(.uppercase)
                                .tracking(0.6)
                                .foregroundStyle(.secondary)
                            VStack(spacing: 0) {
                                ForEach(group.sessions) { session in
                                    if session.id != group.sessions.first?.id {
                                        Divider()
                                    }
                                    HistoryRow(session: session, model: model)
                                }
                            }
                            .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }
            HStack(spacing: 10) {
                Text("Sessions stay on this Mac in Desktop/BetterVoice for up to 7 days.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Open folder", action: model.openSavedSessions)
                    .buttonStyle(.link)
                    .font(.callout)
            }
        }
        .onAppear { model.refresh() }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("No recordings yet", systemImage: "clock.arrow.circlepath")
                .font(.headline)
            Text("Use \(model.hotkeyConfiguration.quick.label) for a quick note or \(model.hotkeyConfiguration.long.label) for a longer explanation. Each transcript and its screenshots will appear here, ready to copy.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 12))
    }

    private func title(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(date: .long, time: .omitted)
    }
}

private struct HistoryRow: View {
    private static let collapsedLineLimit = 5
    private static let longTranscriptLength = 420

    let session: SavedSession
    @ObservedObject var model: SetupModel
    @State private var expanded = false

    private var isLong: Bool { session.transcript.count > Self.longTranscriptLength }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(session.recordedAt.formatted(date: .omitted, time: .shortened))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                if session.transcript.isEmpty {
                    Text("No transcript captured")
                        .foregroundStyle(.secondary)
                } else {
                    // On macOS a selectable Text draws past its line limit once it is
                    // clicked, spilling over the views below. Only the full transcript
                    // is selectable; the truncated preview is plain text.
                    if isLong && !expanded {
                        Text(session.transcript)
                            .lineLimit(Self.collapsedLineLimit)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(session.transcript)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if isLong {
                        Button(expanded ? "Show less" : "Show more") { expanded.toggle() }
                            .buttonStyle(.link)
                            .font(.callout)
                    }
                }
                if !session.images.isEmpty {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 150, maximum: 210), spacing: 10, alignment: .top)],
                        alignment: .leading,
                        spacing: 10
                    ) {
                        ForEach(Array(session.images.enumerated()), id: \.element) { index, image in
                            HistoryThumbnail(
                                url: image,
                                label: "screenshot \(index + 1)",
                                copy: { model.copyImage(image) }
                            )
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 2) {
                if !session.transcript.isEmpty {
                    CopyButton(label: "Copy text", systemImage: "doc.on.doc") {
                        model.copyText(session.transcript)
                    }
                }
                if !session.images.isEmpty {
                    CopyButton(label: "Copy text and screenshots", systemImage: "photo.on.rectangle.angled") {
                        model.copySession(session)
                    }
                }
            }
            .frame(width: 54, alignment: .trailing)
        }
        .padding(14)
    }
}

private struct HistoryThumbnail: View {
    let url: URL
    let label: String
    let copy: () -> Bool
    @State private var image: NSImage?

    private var aspectRatio: CGFloat {
        guard let size = image?.size, size.height > 0 else { return 1.6 }
        return size.width / size.height
    }

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            }
            .aspectRatio(aspectRatio, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
        }
        .buttonStyle(.plain)
        .help("Open \(label)")
        .accessibilityLabel("Open \(label)")
        .overlay(alignment: .topTrailing) {
            CopyButton(label: "Copy \(label)", systemImage: "doc.on.doc", action: copy)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                .padding(6)
        }
        .task(id: url) {
            image = await HistoryThumbnailLoader.thumbnail(for: url)
        }
    }
}

private struct CopyButton: View {
    let label: String
    let systemImage: String
    let action: () -> Bool
    @State private var copied = false

    var body: some View {
        Button {
            guard action() else { return }
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.4))
                copied = false
            }
        } label: {
            Image(systemName: copied ? "checkmark" : systemImage)
                .foregroundStyle(copied ? Color.green : Color.secondary)
                .frame(width: 26, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(copied ? "Copied" : label)
        .accessibilityLabel(label)
    }
}

/// Screenshots are full-display PNGs, so History decodes small previews off the main thread.
@MainActor
private enum HistoryThumbnailLoader {
    private static let cache = NSCache<NSURL, NSImage>()

    static func thumbnail(for url: URL, maxPixelSize: Int = 480) async -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        let decoded = await Task.detached(priority: .utility) { () -> CGImage? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }.value
        guard let decoded else { return nil }
        let image = NSImage(cgImage: decoded, size: NSSize(width: decoded.width, height: decoded.height))
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}
