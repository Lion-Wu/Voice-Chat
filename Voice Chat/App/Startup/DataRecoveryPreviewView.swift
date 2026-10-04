import SwiftUI

struct DataRecoveryPreviewView: View {
    @ObservedObject var coordinator: StartupDataCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingRecovery = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if coordinator.isScanningRecovery {
                        ProgressView("Scanning Recoverable Data...")
                            .frame(maxWidth: .infinity, minHeight: 180)
                    } else if let plan = coordinator.recoveryPlan {
                        ForEach(plan.categories) { category in
                            categoryView(category)
                        }
                        if plan.recoveredCount == 0 {
                            Text("No recoverable records were found. Your original data has not been changed.")
                                .foregroundStyle(.orange)
                        }
                    }
                    if let error = coordinator.recoveryError {
                        Text("Recovery Could Not Be Completed")
                            .font(.headline)
                        Text("Your original data has not been changed.")
                            .foregroundStyle(.secondary)
                        Text(error)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Data Recovery")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        coordinator.cancelRecovery()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Restore Recoverable Data") {
                        isConfirmingRecovery = true
                    }
                    .disabled(coordinator.isScanningRecovery || (coordinator.recoveryPlan?.recoveredCount ?? 0) == 0)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 540, idealWidth: 620, minHeight: 480, idealHeight: 650)
        #endif
        .alert("Restore Data?", isPresented: $isConfirmingRecovery) {
            Button("Cancel", role: .cancel) {}
            Button("Restore Recoverable Data", role: .destructive) { coordinator.confirmRecovery() }
        } message: {
            Text("Only recoverable data will be kept. All other local data will be deleted. This cannot be undone. Export your data first if you want to keep a copy.")
        }
    }

    private func categoryView(_ category: DataRecoveryCategory) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(category.title).font(.headline)
            LabeledContent("Recoverable", value: category.recovered.formatted())
            LabeledContent("Unrecoverable", value: category.hasUnknownLoss ? String(localized: "Unknown") : category.skipped.formatted())
            if category.hasPartialLoss {
                Text("Some content could not be recovered.").foregroundStyle(.orange)
            }
            if !category.names.isEmpty {
                DisclosureGroup("Recovered Items") {
                    itemNames(category.names)
                }
            }
            if !category.skippedNames.isEmpty {
                DisclosureGroup("Unrecoverable Items") {
                    itemNames(category.skippedNames)
                }
            }
        }
        .padding(16)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
    }

    private func itemNames(_ names: [String]) -> some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(names.indices, id: \.self) { index in
                Text(names[index])
                    .font(.callout)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
    }
}
