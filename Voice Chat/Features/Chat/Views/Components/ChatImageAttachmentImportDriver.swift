//
//  ChatImageAttachmentImportDriver.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

#if os(iOS) || os(macOS) || os(visionOS)
import Foundation
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

#if os(iOS)
import UIKit
#endif

@MainActor
final class ChatImageAttachmentImportDriver: ObservableObject {
    @Published var showPhotoPicker = false
    @Published var showFileImporter = false
    @Published var pickedPhotoItems: [PhotosPickerItem] = []
    @Published var pendingPreviewFileURL: URL?
    @Published var showSystemCameraCapture = false
    @Published var isDropTargeted = false
    @Published var dropSuppressionState: ImageDropSuppressionState?

    private var coordinator = ChatImageAttachmentImportCoordinator()

    var acceptedDropTypeIdentifiers: [String] {
        [UTType.image.identifier, UTType.fileURL.identifier]
    }

    func remainingSlots(for viewModel: ChatViewModel) -> Int {
        ChatImageAttachmentImportCoordinator.remainingSlots(
            currentCount: viewModel.pendingImageAttachments.count
        )
    }

    func presentPendingAttachmentPreview(_ attachment: ChatImageAttachment) {
        let previous = pendingPreviewFileURL
        pendingPreviewFileURL = ChatImageQuickLookSupport.prepareTemporaryPreviewURL(for: attachment)
        if previous != pendingPreviewFileURL {
            ChatImageQuickLookSupport.cleanupTemporaryPreviewURL(previous)
        }
    }

    func cleanupPendingPreview() {
        ChatImageQuickLookSupport.cleanupTemporaryPreviewURL(pendingPreviewFileURL)
        pendingPreviewFileURL = nil
    }

    func cancelAll() {
        coordinator.cancelAll()
    }

    func presentSystemCameraCapture(errorCenter: AppErrorCenter) {
        #if os(iOS)
        guard UIImagePickerController.isSourceTypeAvailable(.camera),
              UIImagePickerController.availableMediaTypes(for: .camera)?.contains(UTType.image.identifier) == true else {
            presentCameraUnavailableNotice(errorCenter: errorCenter)
            return
        }
        showSystemCameraCapture = true
        #elseif os(macOS)
        showSystemCameraCapture = true
        #else
        presentCameraUnavailableNotice(errorCenter: errorCenter)
        #endif
    }

    func importCapturedPhotoData(
        _ data: Data,
        mimeType: String?,
        viewModel: ChatViewModel,
        errorCenter: AppErrorCenter,
        focusInput: @escaping () -> Void
    ) {
        #if os(visionOS)
        _ = data
        _ = mimeType
        _ = viewModel
        _ = focusInput
        presentCameraUnavailableNotice(errorCenter: errorCenter)
        #else
        guard viewModel.currentModelSupportsImageInput() else { return }
        guard !data.isEmpty else {
            presentCameraCaptureFailureNotice(errorCenter: errorCenter)
            return
        }
        guard case .accepted = ChatImageAttachmentImportCoordinator.limitDecision(
            requestedCount: 1,
            currentCount: viewModel.pendingImageAttachments.count
        ) else {
            presentImageAttachmentLimitNotice(errorCenter: errorCenter)
            return
        }

        let payload = ChatImageImportPayload(data: data, mimeType: mimeType)
        startImageImport(
            viewModel: viewModel,
            errorCenter: errorCenter,
            focusInput: focusInput
        ) { limit in
            await ChatImageAttachmentImporter.loadImageAttachments(from: [payload], limit: limit)
        }
        #endif
    }

    func importPickedPhotoItems(
        _ items: [PhotosPickerItem],
        viewModel: ChatViewModel,
        errorCenter: AppErrorCenter,
        focusInput: @escaping () -> Void
    ) {
        guard !items.isEmpty else { return }
        switch ChatImageAttachmentImportCoordinator.limitDecision(
            requestedCount: items.count,
            currentCount: viewModel.pendingImageAttachments.count
        ) {
        case .rejected:
            pickedPhotoItems.removeAll()
            presentImageAttachmentLimitNotice(errorCenter: errorCenter)
        case let .accepted(limit, didOverflow):
            if didOverflow {
                presentImageAttachmentOverflowNotice(remainingSlots: limit, errorCenter: errorCenter)
            }
            let snapshot = Array(items.prefix(limit))
            startImageImport(
                source: .photoPicker,
                cancelsEarlierPhotoImports: true,
                viewModel: viewModel,
                errorCenter: errorCenter,
                focusInput: focusInput
            ) { limit in
                await ChatImageAttachmentImporter.loadImageAttachments(from: snapshot, limit: limit)
            }
        }
    }

    func importSelectedImageFiles(
        _ result: Result<[URL], any Error>,
        viewModel: ChatViewModel,
        errorCenter: AppErrorCenter,
        focusInput: @escaping () -> Void
    ) {
        switch result {
        case .success(let urls):
            guard viewModel.currentModelSupportsImageInput() else { return }
            guard !urls.isEmpty else { return }
            switch ChatImageAttachmentImportCoordinator.limitDecision(
                requestedCount: urls.count,
                currentCount: viewModel.pendingImageAttachments.count
            ) {
            case .rejected:
                presentImageAttachmentLimitNotice(errorCenter: errorCenter)
            case let .accepted(limit, didOverflow):
                if didOverflow {
                    presentImageAttachmentOverflowNotice(remainingSlots: limit, errorCenter: errorCenter)
                }
                let limitedURLs = Array(urls.prefix(limit))
                startImageImport(
                    viewModel: viewModel,
                    errorCenter: errorCenter,
                    focusInput: focusInput
                ) { limit in
                    await ChatImageAttachmentImporter.loadImageAttachments(fromFileURLs: limitedURLs, limit: limit)
                }
            }
        case .failure(let error):
            guard !ChatImageAttachmentImporter.isUserCancelledImageImport(error) else { return }
            errorCenter.publish(
                title: NSLocalizedString("Image Import Failed", comment: "Title shown when importing selected image files fails"),
                message: error.localizedDescription,
                category: .textModel
            )
        }
    }

    func importDroppedImageProviders(
        _ providers: [NSItemProvider],
        viewModel: ChatViewModel,
        errorCenter: AppErrorCenter,
        focusInput: @escaping () -> Void
    ) {
        guard viewModel.currentModelSupportsImageInput() else { return }
        guard !providers.isEmpty else { return }
        switch ChatImageAttachmentImportCoordinator.limitDecision(
            requestedCount: providers.count,
            currentCount: viewModel.pendingImageAttachments.count
        ) {
        case .rejected:
            presentImageAttachmentLimitNotice(errorCenter: errorCenter)
        case let .accepted(limit, didOverflow):
            if didOverflow {
                presentImageAttachmentOverflowNotice(remainingSlots: limit, errorCenter: errorCenter)
            }
            let limitedProviders = Array(providers.prefix(limit))
            startImageImport(
                viewModel: viewModel,
                errorCenter: errorCenter,
                focusInput: focusInput
            ) { limit in
                await ChatImageAttachmentImporter.loadImageAttachments(fromItemProviders: limitedProviders, limit: limit)
            }
        }
    }

    func importPastedImages(
        _ payloads: [(data: Data, mimeType: String?)],
        viewModel: ChatViewModel,
        errorCenter: AppErrorCenter,
        focusInput: @escaping () -> Void
    ) {
        guard viewModel.currentModelSupportsImageInput() else { return }
        switch ChatImageAttachmentImportCoordinator.limitDecision(
            requestedCount: payloads.count,
            currentCount: viewModel.pendingImageAttachments.count
        ) {
        case .rejected:
            presentImageAttachmentLimitNotice(errorCenter: errorCenter)
        case let .accepted(limit, didOverflow):
            if didOverflow {
                presentImageAttachmentOverflowNotice(remainingSlots: limit, errorCenter: errorCenter)
            }
            let importPayloads = payloads.prefix(limit).map { payload in
                ChatImageImportPayload(data: payload.data, mimeType: payload.mimeType)
            }
            startImageImport(
                viewModel: viewModel,
                errorCenter: errorCenter,
                focusInput: focusInput
            ) { limit in
                await ChatImageAttachmentImporter.loadImageAttachments(from: importPayloads, limit: limit)
            }
        }
    }

    func appendPendingImageAttachments(
        _ attachments: [ChatImageAttachment],
        viewModel: ChatViewModel,
        errorCenter: AppErrorCenter,
        focusInput: () -> Void
    ) {
        guard !attachments.isEmpty else { return }
        switch ChatImageAttachmentImportCoordinator.limitDecision(
            requestedCount: attachments.count,
            currentCount: viewModel.pendingImageAttachments.count
        ) {
        case .rejected:
            presentImageAttachmentLimitNotice(errorCenter: errorCenter)
        case let .accepted(limit, didOverflow):
            if didOverflow {
                presentImageAttachmentOverflowNotice(remainingSlots: limit, errorCenter: errorCenter)
            }

            let limitedAttachments = Array(attachments.prefix(limit))
            guard !limitedAttachments.isEmpty else { return }

            viewModel.pendingImageAttachments.append(contentsOf: limitedAttachments)
            focusInput()
        }
    }

    func presentImageAttachmentLimitNotice(errorCenter: AppErrorCenter) {
        errorCenter.publish(
            title: NSLocalizedString("Too Many Images", comment: "Title shown when no more image attachments can be added"),
            message: String(
                format: NSLocalizedString(
                    "A message can include up to %lld image attachments.",
                    comment: "Shown when the user reaches the per-message image attachment cap"
                ),
                Int64(ChatImageAttachmentImportCoordinator.maximumAttachmentCount)
            ),
            category: .textModel
        )
    }

    func presentImageAttachmentOverflowNotice(remainingSlots: Int, errorCenter: AppErrorCenter) {
        guard remainingSlots > 0 else {
            presentImageAttachmentLimitNotice(errorCenter: errorCenter)
            return
        }

        errorCenter.publish(
            title: NSLocalizedString("Too Many Images", comment: "Title shown when the user imports more images than the current draft can accept"),
            message: String(
                format: NSLocalizedString(
                    "This message can include %lld additional image attachments. Extra images were ignored.",
                    comment: "Shown when imported images exceed the remaining attachment slots in the current draft"
                ),
                Int64(remainingSlots)
            ),
            category: .textModel
        )
    }

    func presentCameraUnavailableNotice(errorCenter: AppErrorCenter) {
        errorCenter.publish(
            title: NSLocalizedString("Camera Unavailable", comment: "Title shown when the device cannot present the system camera UI"),
            message: NSLocalizedString("This device does not support photo capture.", comment: "Shown when the current device cannot take photos with the system camera UI"),
            category: .textModel
        )
    }

    func presentCameraCaptureFailureNotice(errorCenter: AppErrorCenter) {
        errorCenter.publish(
            title: NSLocalizedString("Camera Capture Failed", comment: "Title shown when the system camera UI returns no usable photo"),
            message: NSLocalizedString("The captured photo could not be imported.", comment: "Shown when a captured photo cannot be converted into an attachment"),
            category: .textModel
        )
    }

    private func startImageImport(
        source: ChatImageAttachmentImportSource = .other,
        cancelsEarlierPhotoImports: Bool = false,
        viewModel: ChatViewModel,
        errorCenter: AppErrorCenter,
        focusInput: @escaping () -> Void,
        _ loader: @escaping (Int) async -> [ChatImageAttachment]
    ) {
        let importLimit = remainingSlots(for: viewModel)
        guard importLimit > 0 else {
            if source == .photoPicker {
                pickedPhotoItems.removeAll()
                coordinator.clearActivePhotoImport()
            }
            return
        }

        let importID = coordinator.beginImport(
            source: source,
            cancelsEarlierPhotoImports: cancelsEarlierPhotoImports
        )

        let task = Task(priority: .utility) { @MainActor [weak self, viewModel, errorCenter] in
            let imported = await loader(importLimit)
            guard let self else { return }
            guard !Task.isCancelled else {
                self.coordinator.finishCancelledImport(id: importID)
                return
            }

            let completion = self.coordinator.completeImport(
                id: importID,
                source: source
            )
            guard case let .apply(clearPhotoSelection) = completion else {
                return
            }
            guard viewModel.currentModelSupportsImageInput() else {
                if clearPhotoSelection {
                    self.pickedPhotoItems.removeAll()
                }
                return
            }

            self.appendPendingImageAttachments(
                imported,
                viewModel: viewModel,
                errorCenter: errorCenter,
                focusInput: focusInput
            )
            if clearPhotoSelection {
                self.pickedPhotoItems.removeAll()
            }
        }
        coordinator.registerTask(task, id: importID)
    }
}
#endif
