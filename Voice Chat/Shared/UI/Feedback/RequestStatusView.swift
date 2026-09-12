import SwiftUI

/// Shared content for request waits, automatic retries, and actionable failures.
struct RequestStatusView: View {
    let title: String
    let message: String?
    var isFailure = false
    var onRetry: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if isFailure {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(.red)
                        .accessibilityHidden(true)
                } else {
                    LoadingIndicatorView(dotSize: 6, spacing: 4)
                }
                Text(title)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(isFailure ? Color.red : Color.secondary)
            }

            if let message, !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let onRetry {
                Button(action: onRetry) {
                    Label(String(localized: "Retry"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
