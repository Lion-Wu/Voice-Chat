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
    @Published private(set) var isExporting = false
    @Published private(set) var isScanningRecovery = false
    @Published private(set) var recoveryPlan: DataRecoveryPlan?
    @Published private(set) var recoveryError: String?
    @Published private(set) var recoveryCleanupError: String?
    private var recoveryTask: Task<Void, Never>?
    var isRecoveryActive: Bool { isScanningRecovery || recoveryPlan != nil }
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
        guard !isResettingStore, !isRecoveryActive, !isExporting else { return }
        activeOperationID = UUID()
        launchState = .failed(Self.formatErrorMessage(error))
    }

    func resetDataAndRetry() {
        guard !isResettingStore, !isRecoveryActive, !isExporting else { return }
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

    func exportData() async throws -> RawDataExport {
        guard case .failed = launchState, !isResettingStore, !isRecoveryActive, !isExporting else {
            throw CocoaError(.userCancelled)
        }
        onWillResetPersistentStore?()
        isExporting = true
        do {
            return try await Task.detached(priority: .userInitiated) {
                try RawDataExport.applicationSnapshot()
            }.value
        } catch {
            isExporting = false
            throw error
        }
    }

    func finishExport(_ archive: RawDataExport?) {
        archive?.discard()
        isExporting = false
    }

    func exitApplication() {
        #if os(macOS)
        NSApp.terminate(nil)
        #else
        exit(0)
        #endif
    }

    /// Builds the selected SwiftData container, including confirmed recoveries.
    private nonisolated static func makeContainer() throws -> ModelContainer {
        try StartupPersistentStore.open(at: StartupPersistentStore.currentURL())
    }

    func scanForRecoverableData() {
        guard !isResettingStore, !isRecoveryActive, !isExporting else { return }
        guard case .failed = launchState else { return }
        onWillResetPersistentStore?()
        recoveryError = nil
        recoveryCleanupError = nil
        isScanningRecovery = true
        recoveryTask = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let plan = try StartupDataRecovery.prepare(
                    sourceURL: StartupPersistentStore.currentURL(),
                    recoveryDirectory: StartupPersistentStore.recoveryDirectory
                )
                guard let self else {
                    plan.discard()
                    return
                }
                await self.finishRecoveryScan(.success(plan))
            } catch {
                await self?.finishRecoveryScan(.failure(error))
            }
        }
    }

    private func finishRecoveryScan(_ result: Result<DataRecoveryPlan, Error>) {
        guard !Task.isCancelled else {
            if case .success(let plan) = result { plan.discard() }
            return
        }
        recoveryTask = nil
        isScanningRecovery = false
        switch result {
        case .success(let plan): recoveryPlan = plan
        case .failure(let error): recoveryError = Self.formatErrorMessage(error)
        }
    }

    func cancelRecovery() {
        recoveryTask?.cancel()
        recoveryTask = nil
        isScanningRecovery = false
        recoveryPlan?.discard()
        recoveryPlan = nil
        recoveryError = nil
    }

    func confirmRecovery() {
        guard let plan = recoveryPlan, plan.recoveredCount > 0 else { return }
        recoveryError = nil
        do {
            try StartupPersistentStore.activate(plan)
            recoveryPlan = nil
            launchState = .loading
            prepareContainer(plan.container)
            guard case .loading = launchState else { return }
            launchState = .ready(plan.container)
            do { try StartupPersistentStore.removeSupersededStores(keeping: plan.storeURL) }
            catch { recoveryCleanupError = Self.formatErrorMessage(error) }
        } catch {
            recoveryError = Self.formatErrorMessage(error)
        }
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

    private static func resetPersistentStoreAsync() async -> Result<Void, Error> {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result: Result<Void, Error>
                do {
                    try StartupPersistentStore.reset()
                    result = .success(())
                } catch {
                    result = .failure(error)
                }
                continuation.resume(returning: result)
            }
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
    @State private var isShowingRecovery = false
    @State private var isShowingCleanupError = false
    @State private var exportArchive: RawDataExport?
    @State private var exportError: String?

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
                    isRecoveryActive: coordinator.isRecoveryActive,
                    isExporting: coordinator.isExporting,
                    onExit: { coordinator.exitApplication() },
                    onReset: { coordinator.resetDataAndRetry() },
                    onRecover: {
                        isShowingRecovery = true
                        coordinator.scanForRecoverableData()
                    },
                    onExport: {
                        Task {
                            do {
                                exportArchive = try await coordinator.exportData()
                            } catch { exportError = error.localizedDescription }
                        }
                    }
                )
            case .ready(let container):
                readyContent(container)
            }
        }
        .background {
            DataExportSharePresenter(url: exportArchive?.url) { _, error in
                if let error {
                    exportError = error.localizedDescription
                }
                coordinator.finishExport(exportArchive)
                exportArchive = nil
            }
            .frame(width: 1, height: 1)
        }
        .alert("Data Export", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: { Text(exportError ?? "") }
        .sheet(isPresented: $isShowingRecovery, onDismiss: {
            coordinator.cancelRecovery()
            isShowingCleanupError = coordinator.recoveryCleanupError != nil
        }) {
            DataRecoveryPreviewView(coordinator: coordinator)
        }
        .alert("Original Data Could Not Be Deleted", isPresented: $isShowingCleanupError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The recovered data is in use, but some original data files could not be deleted.")
            Text(coordinator.recoveryCleanupError ?? "")
        }
        .onChange(of: coordinator.recoveryPlan?.id) { oldValue, newValue in
            if oldValue != nil, newValue == nil { isShowingRecovery = false }
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
    var isRecoveryActive = false
    var isExporting = false
    let onExit: () -> Void
    let onReset: () -> Void
    let onRecover: () -> Void
    let onExport: () -> Void
    @State private var isConfirmingReset = false

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

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { actions }
                    VStack(spacing: 12) { actions }
                }
            }
            .padding(24)
            .frame(maxWidth: 520)
            .appChromedContainer(cornerRadius: 28, shadowOpacity: 0.32)
            .padding(.horizontal, 24)
        }
        .alert("Reset Data?", isPresented: $isConfirmingReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset Data and Continue", role: .destructive, action: onReset)
                .disabled(isResetting || isRecoveryActive || isExporting)
        } message: {
            Text("This will delete your current local chats, messages, settings, and presets. This action cannot be undone.")
        }
    }

    @ViewBuilder
    private var actions: some View {
        Button("Exit", action: onExit)
            .buttonStyle(.bordered)
            .disabled(isResetting || isRecoveryActive || isExporting)

        Button(role: .destructive) {
            isConfirmingReset = true
        } label: {
            HStack(spacing: 8) {
                if isResetting { ProgressView().controlSize(.small) }
                Text(isResetting ? LocalizedStringKey("Resetting...") : LocalizedStringKey("Reset Data and Continue"))
            }
        }
        .buttonStyle(.bordered)
        .tint(.red)
        .foregroundStyle(.red)
        .disabled(isResetting || isRecoveryActive || isExporting)

        Button(action: onExport) {
            Text("Export Data")
                .opacity(isExporting ? 0 : 1)
                .overlay {
                    if isExporting { ProgressView().controlSize(.small) }
                }
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(Text("Export Data"))
        .accessibilityValue(isExporting ? Text("Loading...") : Text(""))
        .disabled(isResetting || isRecoveryActive || isExporting)

        Button("Recover Data", action: onRecover)
            .buttonStyle(.borderedProminent)
            .disabled(isResetting || isRecoveryActive || isExporting)
    }

}

#Preview("Startup Data Error") {
    StartupDataErrorView(
        errorMessage: "The file couldn't be opened because it is corrupted.\n[SwiftData: 42]",
        isResetting: false,
        onExit: {},
        onReset: {},
        onRecover: {},
        onExport: {}
    )
}

#Preview("Startup Data Error (Resetting)") {
    StartupDataErrorView(
        errorMessage: "Unable to read SQLite file.\n[NSSQLiteErrorDomain: 11]",
        isResetting: true,
        onExit: {},
        onReset: {},
        onRecover: {},
        onExport: {}
    )
}
