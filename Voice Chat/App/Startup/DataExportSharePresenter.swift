import SwiftUI

#if os(macOS)
import AppKit

struct DataExportSharePresenter: NSViewRepresentable {
    let url: URL?
    let onCompletion: (Bool, Error?) -> Void

    func makeNSView(context: Context) -> NSView { NSView() }
    func makeCoordinator() -> Coordinator { Coordinator(onCompletion: onCompletion) }

    func updateNSView(_ view: NSView, context: Context) {
        guard let url, context.coordinator.picker == nil else { return }
        let picker = NSSharingServicePicker(items: [url])
        context.coordinator.picker = picker
        picker.delegate = context.coordinator
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    final class Coordinator: NSObject, NSSharingServicePickerDelegate, NSSharingServiceDelegate {
        var picker: NSSharingServicePicker?
        let onCompletion: (Bool, Error?) -> Void

        init(onCompletion: @escaping (Bool, Error?) -> Void) {
            self.onCompletion = onCompletion
        }

        func sharingServicePicker(_ picker: NSSharingServicePicker, didChoose service: NSSharingService?) {
            if service == nil { finish(completed: false) }
        }

        func sharingServicePicker(_ picker: NSSharingServicePicker, delegateFor service: NSSharingService) -> (any NSSharingServiceDelegate)? {
            self
        }

        func sharingService(_ service: NSSharingService, didShareItems items: [Any]) {
            finish(completed: true)
        }

        func sharingService(_ service: NSSharingService, didFailToShareItems items: [Any], error: Error) {
            finish(completed: false, error: (error as? CocoaError)?.code == .userCancelled ? nil : error)
        }

        private func finish(completed: Bool, error: Error? = nil) {
            guard picker != nil else { return }
            picker = nil
            onCompletion(completed, error)
        }
    }
}
#else
import UIKit

struct DataExportSharePresenter: UIViewControllerRepresentable {
    let url: URL?
    let onCompletion: (Bool, Error?) -> Void

    func makeUIViewController(context: Context) -> ShareController { ShareController() }

    func updateUIViewController(_ controller: ShareController, context: Context) {
        guard let url, controller.onCompletion == nil else { return }
        controller.onCompletion = onCompletion
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activity.completionWithItemsHandler = { [weak controller] _, completed, _, error in
            controller?.finish(completed: completed, error: error)
        }
        activity.popoverPresentationController?.sourceView = controller.view
        activity.popoverPresentationController?.sourceRect = controller.view.bounds
        activity.popoverPresentationController?.permittedArrowDirections = []
        controller.present(activity, animated: true)
        activity.presentationController?.delegate = controller
    }

    final class ShareController: UIViewController, UIAdaptivePresentationControllerDelegate {
        var onCompletion: ((Bool, Error?) -> Void)?

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            finish(completed: false)
        }

        func finish(completed: Bool, error: Error? = nil) {
            let completion = onCompletion
            onCompletion = nil
            completion?(completed, error)
        }
    }
}
#endif
