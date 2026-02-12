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
    enum LaunchState {
        case checking
        case ready(ModelContainer)
        case failed(String)
    }

    @Published private(set) var launchState: LaunchState = .checking
    @Published private(set) var isResettingStore = false
    private var isBootstrappingStore = false
    private var activeOperationID = UUID()

    func bootstrapPersistentStoreIfNeeded() {
        guard case .checking = launchState else { return }
        guard !isBootstrappingStore else { return }
        isBootstrappingStore = true
        let operationID = UUID()
        activeOperationID = operationID

        Task { [operationID] in
            let result = await Self.makeContainerAndValidateAsync()
            isBootstrappingStore = false
            guard activeOperationID == operationID else { return }
            guard case .checking = launchState else { return }

            switch result {
            case .success(let container):
                launchState = .ready(container)
            case .failure(let error):
                launchState = .failed(Self.formatErrorMessage(error))
            }
        }
    }

    func resetDataAndRetry() {
        guard !isResettingStore else { return }
        isResettingStore = true
        // Any ongoing bootstrap result is now stale once reset starts.
        isBootstrappingStore = false
        let operationID = UUID()
        activeOperationID = operationID

        Task { [operationID] in
            let result = await Self.resetPersistentStoreAsync()
            guard activeOperationID == operationID else { return }

            isResettingStore = false
            switch result {
            case .success:
                launchState = .checking
                bootstrapPersistentStoreIfNeeded()
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

    /// Runs container init and lightweight validation off the main thread.
    private static func makeContainerAndValidateAsync() async -> Result<ModelContainer, Error> {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result: Result<ModelContainer, Error>
                do {
                    result = .success(try makeContainerAndValidate())
                } catch {
                    result = .failure(error)
                }
                continuation.resume(returning: result)
            }
        }
    }

    /// Ensures all key entities can be read before entering the app UI.
    private nonisolated static func makeContainerAndValidate() throws -> ModelContainer {
        let container = try makeContainer()
        try validatePersistentStoreReadability(in: container)
        return container
    }

    private nonisolated static func validatePersistentStoreReadability(in container: ModelContainer) throws {
        let context = ModelContext(container)
        // One lightweight read is enough to verify local data is readable at startup.
        try validateModelReadability(AppSettings.self, in: context)
    }

    private nonisolated static func validateModelReadability<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws {
        var descriptor = FetchDescriptor<T>()
        descriptor.fetchLimit = 1
        descriptor.includePendingChanges = false
        _ = try context.fetchIdentifiers(descriptor)
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

struct StartupDataGateView<ReadyContent: View>: View {
    @ObservedObject private var coordinator: StartupDataCoordinator
    private let readyContent: (ModelContainer) -> ReadyContent

    init(
        coordinator: StartupDataCoordinator,
        @ViewBuilder readyContent: @escaping (ModelContainer) -> ReadyContent
    ) {
        self.coordinator = coordinator
        self.readyContent = readyContent
    }

    var body: some View {
        Group {
            switch coordinator.launchState {
            case .checking:
                StartupDataLoadingView()
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
        .task {
            coordinator.bootstrapPersistentStoreIfNeeded()
        }
    }
}

/// Shown while startup is verifying the persistent store.
struct StartupDataLoadingView: View {
    var body: some View {
        ZStack {
            AppBackgroundView()
            VStack(spacing: 12) {
                ProgressView()
                Text("Checking data...")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
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
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.thinMaterial)
                )

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
                            Text(isResetting ? "Resetting..." : "Reset Data and Continue")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isResetting)
                }
            }
            .padding(24)
            .frame(maxWidth: 520)
        }
    }
}

#Preview("Startup Data Loading") {
    StartupDataLoadingView()
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
