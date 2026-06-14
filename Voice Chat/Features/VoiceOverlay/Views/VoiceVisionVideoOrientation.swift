#if os(iOS)

import SwiftUI
@preconcurrency import AVFoundation

enum VoiceVisionVideoOrientation: Equatable {
    case portrait
    case portraitUpsideDown
    case landscapeLeft
    case landscapeRight

    init(interfaceOrientation: UIInterfaceOrientation?) {
        switch interfaceOrientation {
        case .portrait:
            self = .portrait
        case .portraitUpsideDown:
            self = .portraitUpsideDown
        case .landscapeLeft:
            self = .landscapeLeft
        case .landscapeRight:
            self = .landscapeRight
        case .unknown, .none:
            self = .portrait
        @unknown default:
            self = .portrait
        }
    }

    var rotationAngle: CGFloat {
        switch self {
        case .portrait:
            return 90
        case .portraitUpsideDown:
            return 270
        case .landscapeRight:
            return 0
        case .landscapeLeft:
            return 180
        }
    }
}

extension AVCaptureConnection {
    func applyVoiceVisionOrientation(_ orientation: VoiceVisionVideoOrientation) {
        let angle = orientation.rotationAngle
        if isVideoRotationAngleSupported(angle) {
            videoRotationAngle = angle
        }
    }
}

#endif
