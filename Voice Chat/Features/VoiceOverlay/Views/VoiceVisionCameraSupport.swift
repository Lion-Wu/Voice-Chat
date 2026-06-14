#if os(iOS) || os(macOS)

import Foundation

enum VoiceVisionCameraError: LocalizedError {
    case noCameraAvailable
    case unableToAddInput
    case unableToAddOutput

    var errorDescription: String? {
        switch self {
        case .noCameraAvailable:
            return NSLocalizedString("No camera was found for photo capture.", comment: "Shown when voice vision camera cannot find a camera")
        case .unableToAddInput, .unableToAddOutput:
            return NSLocalizedString("Camera Capture Failed", comment: "Title shown when the camera cannot be configured")
        }
    }
}

extension Optional {
    func orThrow(_ error: any Error) throws -> Wrapped {
        guard let self else { throw error }
        return self
    }
}

#endif
