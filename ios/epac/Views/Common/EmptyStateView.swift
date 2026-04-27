import SwiftUI

/// A reusable empty-state view with a large SF Symbol, title, message, and optional CTA.
/// All six canonical empty states in the app use this component.
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var action: EmptyStateAction? = nil

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let action {
                Button(action.label, action: action.handler)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(!action.isEnabled)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptyStateAction {
    let label: String
    var isEnabled: Bool = true
    let handler: () -> Void
}
