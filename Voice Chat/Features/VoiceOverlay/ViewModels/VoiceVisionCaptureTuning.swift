import Foundation

enum VoiceVisionCaptureTuning {
    static let sampleInterval: TimeInterval = 2.0
    static let sampleIntervalNanoseconds = UInt64(sampleInterval * 1_000_000_000)

    static let sampledImageMaxPixelSize = 960.0
    static let jpegCompressionQuality = 0.68

    static let fingerprintGridDimension = 8
    static let fingerprintImageMaxPixelSize = 64
    static let fingerprintSubsamplesPerCell = 2
    static let maximumAttachmentCount = ChatImageAttachmentLimits.maximumAttachmentCount
    static let encodingDuplicateThreshold = 4.0
    static let maxRecentEncodedFingerprints = maximumAttachmentCount
    static let selectionDistinctThreshold = 18.0
    static let attachmentCountSaturationDuration: TimeInterval = 60.0
}
