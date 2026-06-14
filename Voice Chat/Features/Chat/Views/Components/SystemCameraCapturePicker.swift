//
//  SystemCameraCapturePicker.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.13.
//

#if os(iOS)
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
struct SystemCameraCapturePicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onCapture: (Data, String?) -> Void
    let onFailure: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.mediaTypes = [UTType.image.identifier]
        picker.allowsEditing = false
        picker.showsCameraControls = true
        if UIImagePickerController.isCameraDeviceAvailable(.rear) {
            picker.cameraDevice = .rear
        }
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        var parent: SystemCameraCapturePicker

        init(parent: SystemCameraCapturePicker) {
            self.parent = parent
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.isPresented = false
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            defer { parent.isPresented = false }

            if let imageURL = info[.imageURL] as? URL,
               let fileData = try? Data(contentsOf: imageURL),
               !fileData.isEmpty {
                let mimeType = UTType(filenameExtension: imageURL.pathExtension)?.preferredMIMEType
                parent.onCapture(fileData, mimeType)
                return
            }

            let selectedImage = (info[.editedImage] ?? info[.originalImage]) as? UIImage
            guard let imageData = selectedImage?.jpegData(compressionQuality: 0.92), !imageData.isEmpty else {
                parent.onFailure()
                return
            }

            parent.onCapture(imageData, "image/jpeg")
        }
    }
}
#endif
