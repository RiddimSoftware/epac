import SwiftUI

struct HomeRefreshErrorToast: View {
    var body: some View {
        Label(
            NSLocalizedString("home.refresh.offlineError", comment: ""),
            systemImage: "wifi.exclamationmark"
        )
        .font(.epacCaption.weight(.medium))
        .foregroundStyle(Color.epacText.onAccent)
        .padding(.horizontal, EpacSpacing.m)
        .padding(.vertical, EpacSpacing.s)
        .background(Color.epacStatus.warning)
        .clipShape(Capsule())
        .padding(.top, EpacSpacing.m)
        .accessibilityIdentifier("homeRefreshErrorToast")
    }
}
