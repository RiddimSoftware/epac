import SwiftUI

/// A reusable empty-state view with a large SF Symbol, title, message, and optional CTA.
/// All six canonical empty states in the app use this component.
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var action: EmptyStateAction?

    private enum Layout {
        static let textSpacing: CGFloat = 6
    }

    var body: some View {
        VStack(spacing: EpacSpacing.m) {
            Image(systemName: icon)
                .font(.system(size: EpacIconSize.xl, weight: .thin))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(spacing: Layout.textSpacing) {
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
        .padding(EpacSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptyStateAction {
    let label: String
    var isEnabled: Bool = true
    let handler: () -> Void
}
