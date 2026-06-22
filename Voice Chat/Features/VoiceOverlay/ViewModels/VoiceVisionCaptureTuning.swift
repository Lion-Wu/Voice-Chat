import Foundation

enum VoiceVisionCaptureTuning {
    static let sampleInterval: TimeInterval = 2.0
    static let sampleIntervalNanoseconds = UInt64(sampleInterval * 1_000_000_000)

    static let sampledImageMaxPixelSize = 1280.0
    static let jpegCompressionQuality = 0.78

    static let fingerprintGridDimension = 12
    static let fingerprintImageMaxPixelSize = 96
    static let fingerprintSubsamplesPerCell = 2
    static let fingerprintMaxShiftFraction = 0.375
    static let fingerprintShiftCoveragePenalty = 6.0
    static let maximumAttachmentCount = ChatImageAttachmentLimits.maximumAttachmentCount
    static let encodingDuplicateThreshold = 10.0
    static let maxRecentEncodedFingerprints = maximumAttachmentCount
    static let selectionDistinctThreshold = 24.0
    static let attachmentCountSaturationDuration: TimeInterval = 120.0
}
