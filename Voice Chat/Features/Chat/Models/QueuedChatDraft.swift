import Foundation

struct QueuedChatDraft: Identifiable, Equatable, Sendable {
    var id: UUID
    var text: String
    var imageAttachments: [ChatImageAttachment]
    var editingBaseMessageID: UUID?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        text: String,
        imageAttachments: [ChatImageAttachment] = [],
        editingBaseMessageID: UUID? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.imageAttachments = imageAttachments
        self.editingBaseMessageID = editingBaseMessageID
        self.createdAt = createdAt
    }
}

extension QueuedChatDraft {
    var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isEmpty: Bool {
        trimmedText.isEmpty && imageAttachments.isEmpty
    }

    var previewText: String {
        let collapsed = trimmedText.replacingOccurrences(of: "\n", with: " ")
        if !collapsed.isEmpty {
            return collapsed
        }
        return String(localized: "Image-only message")
    }
}
