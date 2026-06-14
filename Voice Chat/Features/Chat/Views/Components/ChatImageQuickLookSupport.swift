//
//  ChatImageQuickLookSupport.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

#if os(iOS) || os(macOS) || os(visionOS)
import Foundation
import UniformTypeIdentifiers

@MainActor
enum ChatImageQuickLookSupport {
    private static let directoryName = "VoiceChatQuickLook"

    static func prepareTemporaryPreviewURL(for attachment: ChatImageAttachment) -> URL? {
        let fileManager = FileManager.default
        let directoryURL = fileManager.temporaryDirectory
            .appendingPathComponent(directoryName, isDirectory: true)

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        let fileExtension = preferredFileExtension(for: attachment.mimeType)
        let filename = "attachment-\(attachment.id.uuidString)-\(UUID().uuidString).\(fileExtension)"
        let fileURL = directoryURL.appendingPathComponent(filename, isDirectory: false)

        do {
            try attachment.data.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            return nil
        }
    }

    static func cleanupTemporaryPreviewURL(_ fileURL: URL?) {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static func preferredFileExtension(for mimeType: String) -> String {
        let normalized = mimeType
            .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        if let type = UTType(mimeType: normalized),
           let fileExtension = type.preferredFilenameExtension,
           !fileExtension.isEmpty {
            return fileExtension
        }

        switch normalized {
        case "image/jpeg", "image/jpg":
            return "jpg"
        case "image/png":
            return "png"
        case "image/gif":
            return "gif"
        case "image/webp":
            return "webp"
        case "image/heic", "image/heif":
            return "heic"
        case "image/tiff":
            return "tiff"
        case "image/bmp":
            return "bmp"
        default:
            return "jpg"
        }
    }
}
#endif
