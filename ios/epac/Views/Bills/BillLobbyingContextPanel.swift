import SwiftUI

private enum BillLobbyingContextPanelLayout {
	static let rowSpacing = EpacSpacing.xs
	static let stackSpacing = EpacSpacing.s
	static let countWidth: CGFloat = 54
	static let topOrganizationsLimit = 3
}

struct BillLobbyingContextPanel: View {
	let context: BillLobbyingContext

	var body: some View {
		if context.hasCommunications {
			Section(NSLocalizedString("billLobbying.title", comment: "")) {
				VStack(alignment: .leading, spacing: BillLobbyingContextPanelLayout.stackSpacing) {
					Label {
						Text(summaryText)
							.font(.subheadline.weight(.semibold))
							.fixedSize(horizontal: false, vertical: true)
					} icon: {
						Image(systemName: "person.2.wave.2.fill")
							.foregroundStyle(Color.accentColor)
					}

					VStack(alignment: .leading, spacing: BillLobbyingContextPanelLayout.rowSpacing) {
						ForEach(Array(context.topOrganizations.prefix(
							BillLobbyingContextPanelLayout.topOrganizationsLimit
						))) { organization in
							BillLobbyingOrganizationRow(organization: organization)
						}
					}

					LobbyingSourceCitationView(url: context.sourceURL)
				}
				.accessibilityIdentifier("bill-lobbying-context-panel")
			}
		}
	}

	private var summaryText: String {
		String(
			format: NSLocalizedString("billLobbying.summary", comment: ""),
			context.totalCommunications
		)
	}
}

private struct BillLobbyingOrganizationRow: View {
	let organization: BillLobbyingOrganization

	var body: some View {
		HStack(alignment: .firstTextBaseline, spacing: EpacSpacing.s) {
			Text(organization.name)
				.font(.subheadline)
				.fixedSize(horizontal: false, vertical: true)
			Spacer(minLength: EpacSpacing.s)
			Text("\(organization.communicationCount)")
				.font(.subheadline.monospacedDigit().weight(.semibold))
				.frame(width: BillLobbyingContextPanelLayout.countWidth, alignment: .trailing)
				.accessibilityLabel("\(organization.communicationCount) communications")
		}
		.accessibilityElement(children: .combine)
	}
}
