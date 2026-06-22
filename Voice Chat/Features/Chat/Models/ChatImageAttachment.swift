import Foundation

enum ChatImageAttachmentLimits {
    static let maximumAttachmentCount = 9
}

struct ChatImageAttachment: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: UUID
    var mimeType: String
    var data: Data

    init(id: UUID = UUID(), mimeType: String, data: Data) {
        self.id = id
        self.mimeType = mimeType
        self.data = data
    }

    var dataURLString: String {
        "data:\(mimeType);base64,\(data.base64EncodedString())"
    }

    static func encodeList(_ attachments: [ChatImageAttachment]) -> Data? {
        guard !attachments.isEmpty else { return nil }
        return try? JSONEncoder().encode(attachments)
    }

    static func decodeList(from data: Data?) -> [ChatImageAttachment] {
        guard let data, !data.isEmpty else { return [] }
        return (try? JSONDecoder().decode([ChatImageAttachment].self, from: data)) ?? []
    }
}
