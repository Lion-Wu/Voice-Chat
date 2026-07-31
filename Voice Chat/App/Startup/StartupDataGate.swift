//
//  StartupDataGate.swift
//  Voice Chat
//
//  Created by OpenAI Codex on 2026/02/12.
//

import SwiftUI
import SwiftData
import Darwin
#if os(macOS)
import AppKit
#endif

@MainActor
final class StartupDataCoordinator: ObservableObject {
    typealias ContainerFactory = @Sendable () throws -> ModelContainer
    typealias ContainerPreparer = @MainActor (ModelContainer) -> Void

    enum LaunchState {
        case loading
        case ready(ModelContainer)
        case failed(String)
    }

    @Published private(set) var launchState: LaunchState = .loading
    @Published private(set) var isResettingStore = false
    private var activeOperationID = UUID()
    private let containerFactory: ContainerFactory
    private let prepareContainer: ContainerPreparer
    var onWillResetPersistentStore: (() -> Void)?

    init(prepareContainer: @escaping ContainerPreparer = { _ in }) {
        self.containerFactory = Self.makeContainer
        self.prepareContainer = prepareContainer
        beginPersistentContainerLoad()
    }

    init(
        containerFactory: @escaping ContainerFactory,
        prepareContainer: @escaping ContainerPreparer = { _ in }
    ) {
        self.containerFactory = containerFactory
        self.prepareContainer = prepareContainer
        beginPersistentContainerLoad()
    }

    func reportPersistentStoreReadFailure(_ error: Error) {
        guard !isResettingStore else { return }
        activeOperationID = UUID()
        launchState = .failed(Self.formatErrorMessage(error))
    }

    func resetDataAndRetry() {
        guard !isResettingStore else { return }
        onWillResetPersistentStore?()
        isResettingStore = true
        let operationID = UUID()
        activeOperationID = operationID

        Task { [operationID] in
            let result = await Self.resetPersistentStoreAsync()
            guard activeOperationID == operationID else { return }

            isResettingStore = false
            switch result {
            case .success:
                beginPersistentContainerLoad()
            case .failure(let error):
                let template = String(localized: "Reset data failed.\n%@")
                launchState = .failed(String.localizedStringWithFormat(template, Self.formatErrorMessage(error)))
            }
        }
    }

    func exitApplication() {
        #if os(macOS)
        NSApp.terminate(nil)
        #else
        exit(0)
        #endif
    }

    /// Shared schema used for store creation, startup checks, and reset.
    private nonisolated static let persistentSchema = Schema([
        ChatSession.self,
        ChatMessage.self,
        ChatRequestContextMetadata.self,
        AppSettings.self,
        ChatServerPreset.self,
        VoiceServerPreset.self,
        VoicePreset.self,
        SystemPromptPreset.self
    ])

    /// Shared persistent-store configuration, including stable store URL.
    private nonisolated static let persistentConfiguration = ModelConfiguration()

    /// Builds the shared SwiftData container.
    private nonisolated static func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: persistentSchema, configurations: [persistentConfiguration])
    }

    private func beginPersistentContainerLoad() {
        launchState = .loading
        let operationID = UUID()
        activeOperationID = operationID
        let factory = containerFactory

        Task { [weak self] in
            let result = await Self.makeContainerAsync(using: factory)
            guard let self, self.activeOperationID == operationID else { return }
            switch result {
            case .success(let container):
                self.prepareContainer(container)
                guard self.activeOperationID == operationID else { return }
                guard case .loading = self.launchState else { return }
                self.launchState = .ready(container)
            case .failure(let error):
                self.launchState = .failed(Self.formatErrorMessage(error))
            }
        }
    }

    private nonisolated static func makeContainerAsync(
        using factory: @escaping ContainerFactory
    ) async -> Result<ModelContainer, Error> {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: .success(try factory()))
                } catch {
                    continuation.resume(returning: .failure(error))
                }
            }
        }
    }

    private nonisolated static func resetPersistentStore() throws {
        do {
            let container = try makeContainer()
            try eraseData(in: container)
        } catch {
            try removeStoreFiles(at: persistentConfiguration.url)
        }
    }

    private static func resetPersistentStoreAsync() async -> Result<Void, Error> {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result: Result<Void, Error>
                do {
                    try resetPersistentStore()
                    result = .success(())
                } catch {
                    result = .failure(error)
                }
                continuation.resume(returning: result)
            }
        }
    }

    private nonisolated static func eraseData(in container: ModelContainer) throws {
        if #available(iOS 18, macOS 15, tvOS 18, *) {
            try container.erase()
        } else {
            container.deleteAllData()
        }
    }

    private nonisolated static func removeStoreFiles(at storeURL: URL) throws {
        let fileManager = FileManager.default
        let relatedURLs = [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-shm"),
            URL(fileURLWithPath: storeURL.path + "-wal")
        ]

        var firstError: Error?
        for fileURL in relatedURLs {
            guard fileManager.fileExists(atPath: fileURL.path) else { continue }
            do {
                try fileManager.removeItem(at: fileURL)
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }

        if let firstError {
            throw firstError
        }
    }

    private nonisolated static func formatErrorMessage(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.localizedDescription)\n[\(nsError.domain): \(nsError.code)]"
    }
}

struct StartupDataGateView<LoadingContent: View, ReadyContent: View>: View {
    @ObservedObject private var coordinator: StartupDataCoordinator
    private let loadingContent: () -> LoadingContent
    private let readyContent: (ModelContainer) -> ReadyContent

    init(
        coordinator: StartupDataCoordinator,
        @ViewBuilder loadingContent: @escaping () -> LoadingContent,
        @ViewBuilder readyContent: @escaping (ModelContainer) -> ReadyContent
    ) {
        self.coordinator = coordinator
        self.loadingContent = loadingContent
        self.readyContent = readyContent
    }

    var body: some View {
        Group {
            switch coordinator.launchState {
            case .loading:
                loadingContent()
            case .failed(let errorMessage):
                StartupDataErrorView(
                    errorMessage: errorMessage,
                    isResetting: coordinator.isResettingStore,
                    onExit: { coordinator.exitApplication() },
                    onReset: { coordinator.resetDataAndRetry() }
                )
            case .ready(let container):
                readyContent(container)
            }
        }
    }
}

/// Loading content shown inside the normal chat shell while the single
/// persistent container opens in the background.
struct StartupChatLoadingView: View {
    var body: some View {
        ZStack {
            AppBackgroundView()
            ProgressView("Loading chats...")
                .foregroundStyle(.secondary)
        }
    }
}

struct StartupSettingsLoadingView: View {
    var body: some View {
        ZStack {
            AppBackgroundView()
            ProgressView("Loading settings...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Recovery view shown when startup cannot read the persistent store.
struct StartupDataErrorView: View {
    let errorMessage: String
    let isResetting: Bool
    let onExit: () -> Void
    let onReset: () -> Void

    var body: some View {
        ZStack {
            AppBackgroundView()
            VStack(spacing: 18) {
                Image(systemName: "externaldrive.badge.xmark")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.red)

                Text("Data Error")
                    .font(.title3.weight(.semibold))

                Text("The app could not read local data at launch.")
                    .foregroundStyle(.secondary)

                ScrollView {
                    Text(errorMessage)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(maxHeight: 140)
                .appChromedContainer(cornerRadius: 12, shadowOpacity: 0.14)

                HStack(spacing: 12) {
                    Button("Exit") {
                        onExit()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isResetting)

                    Button {
                        onReset()
                    } label: {
                        HStack(spacing: 8) {
                            if isResetting {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(isResetting
                                ? LocalizedStringKey("Resetting...")
                                : LocalizedStringKey("Reset Data and Continue"))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isResetting)
                }
            }
            .padding(24)
            .frame(maxWidth: 520)
            .appChromedContainer(cornerRadius: 28, shadowOpacity: 0.32)
        }
    }
}

#Preview("Startup Data Error") {
    StartupDataErrorView(
        errorMessage: "The file couldn't be opened because it is corrupted.\n[SwiftData: 42]",
        isResetting: false,
        onExit: {},
        onReset: {}
    )
}

#Preview("Startup Data Error (Resetting)") {
    StartupDataErrorView(
        errorMessage: "Unable to read SQLite file.\n[NSSQLiteErrorDomain: 11]",
        isResetting: true,
        onExit: {},
        onReset: {}
    )
}
