//
//  ChatImageDropSupport.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.13.
//

#if os(iOS) || os(macOS) || os(visionOS)
import SwiftUI
import Foundation

struct ImageDropSuppressionState {
    let signature: String
    let expiresAt: Date
}

struct ImageAttachmentDropDelegate: DropDelegate {
    let isEnabled: Bool
    @Binding var isTargeted: Bool
    @Binding var suppressionState: ImageDropSuppressionState?
    let acceptedTypeIdentifiers: [String]
    let filterProviders: ([NSItemProvider]) -> [NSItemProvider]
    let importProviders: ([NSItemProvider]) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        !imageProviders(from: info).isEmpty
    }

    func dropEntered(info: DropInfo) {
        guard !isSuppressed(info: info) else {
            isTargeted = false
            return
        }
        isTargeted = !imageProviders(from: info).isEmpty
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard !isSuppressed(info: info) else {
            isTargeted = false
            return nil
        }
        let hasImageProviders = !imageProviders(from: info).isEmpty
        isTargeted = hasImageProviders
        return hasImageProviders ? DropProposal(operation: .copy) : nil
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
        if suppressionExpired {
            suppressionState = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        let rawProviders = info.itemProviders(for: acceptedTypeIdentifiers)
        let providers = filterProviders(rawProviders)
        if !rawProviders.isEmpty {
            suppressionState = ImageDropSuppressionState(
                signature: Self.providerSignature(for: rawProviders),
                expiresAt: Date().addingTimeInterval(1.5)
            )
        }
        isTargeted = false
        guard !providers.isEmpty else {
            return false
        }
        importProviders(providers)
        return true
    }

    private func imageProviders(from info: DropInfo) -> [NSItemProvider] {
        guard isEnabled, !isSuppressed(info: info) else { return [] }
        return filterProviders(info.itemProviders(for: acceptedTypeIdentifiers))
    }

    private func isSuppressed(info: DropInfo) -> Bool {
        guard let suppressionState else { return false }
        guard !suppressionExpired else {
            self.suppressionState = nil
            return false
        }

        return suppressionState.signature == Self.providerSignature(for: info.itemProviders(for: acceptedTypeIdentifiers))
    }

    private var suppressionExpired: Bool {
        guard let suppressionState else { return true }
        return Date() >= suppressionState.expiresAt
    }

    private static func providerSignature(for providers: [NSItemProvider]) -> String {
        providers.map { provider in
            let name = provider.suggestedName ?? ""
            let types = provider.registeredTypeIdentifiers.sorted().joined(separator: ",")
            return "\(name)|\(types)"
        }
        .joined(separator: "||")
    }
}
#endif
