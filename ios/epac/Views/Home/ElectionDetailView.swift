//
//  ElectionDetailView.swift
//  epac
//

import SwiftUI

private enum ElectionDetailLayout {
	static let cardSpacing: CGFloat = 20
	static let sectionSpacing = EpacSpacing.s
	static let inlineSpacing: CGFloat = 6
	static let cardCornerRadius = EpacCornerRadius.m
	static let sourceSpacing: CGFloat = 6
	static let sourceTopPadding = EpacSpacing.xs
}

// Detail view explaining the fixed-election-date law and linking to
// elections.ca for voter registration. Reachable from the Home feed
// countdown card.
struct ElectionDetailView: View {
	let lastElectionDate: Date
	let mandatedDate: Date
	let daysRemaining: Int

	private static let dateFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateStyle = .long
		formatter.timeStyle = .none
		formatter.timeZone = TimeZone(identifier: "America/Toronto")
		return formatter
	}()

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: ElectionDetailLayout.cardSpacing) {
				headerCard
				explanationCard
				registerCard
				sourceFooter
			}
			.padding()
		}
		.navigationTitle("Next federal election")
		.navigationBarTitleDisplayMode(.inline)
		.accessibilityIdentifier("election-detail-scroll")
	}

	private var headerCard: some View {
		VStack(alignment: .leading, spacing: ElectionDetailLayout.sectionSpacing) {
			Label("Mandated election date", systemImage: "checkmark.seal.fill")
				.font(.headline)
				.foregroundStyle(Color.epacBrand.accent)
			Text(Self.dateFormatter.string(from: mandatedDate))
				.font(.title2.weight(.semibold))
			HStack(spacing: ElectionDetailLayout.inlineSpacing) {
				Image(systemName: "clock")
					.foregroundStyle(.secondary)
				Text(daysRemainingText)
					.font(.subheadline)
					.foregroundStyle(.secondary)
			}
		}
		.padding()
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(Color(.secondarySystemBackground))
		.cornerRadius(ElectionDetailLayout.cardCornerRadius)
	}

	private var explanationCard: some View {
		VStack(alignment: .leading, spacing: ElectionDetailLayout.sectionSpacing) {
			Text("Fixed-election-date law")
				.font(.headline)
			Text("The Canada Elections Act, section 56.1, sets the polling day for each general election as the third Monday of October in the fourth calendar year following polling day for the last general election.")
				.font(.subheadline)
				.fixedSize(horizontal: false, vertical: true)
			Divider()
			Text("Last general election")
				.font(.subheadline.weight(.semibold))
			Text(Self.dateFormatter.string(from: lastElectionDate))
				.font(.subheadline)
				.foregroundStyle(.secondary)
			Text("An election may still be called earlier — for example after a non-confidence vote, or by the Governor General at the Prime Minister's request. If a writ is issued before the mandated date, the writ date supersedes the date shown above.")
				.font(.caption)
				.foregroundStyle(.secondary)
				.fixedSize(horizontal: false, vertical: true)
		}
		.padding()
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(Color(.secondarySystemBackground))
		.cornerRadius(ElectionDetailLayout.cardCornerRadius)
	}

	private var registerCard: some View {
		VStack(alignment: .leading, spacing: ElectionDetailLayout.sectionSpacing) {
			Label("Register to vote", systemImage: "person.crop.circle.badge.checkmark")
				.font(.headline)
			Text("Confirm or update your information on the National Register of Electors with Elections Canada.")
				.font(.subheadline)
				.fixedSize(horizontal: false, vertical: true)
			if let url = URL(string: "https://www.elections.ca/register") {
				Link(destination: url) {
					HStack {
						Text("Open elections.ca")
						Spacer()
						Image(systemName: "arrow.up.right.square")
							.font(.caption)
							.foregroundStyle(.tertiary)
					}
				}
				.foregroundStyle(.primary)
			}
		}
		.padding()
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(Color(.secondarySystemBackground))
		.cornerRadius(ElectionDetailLayout.cardCornerRadius)
		.accessibilityIdentifier("election-detail-register-link")
	}

	private var sourceFooter: some View {
		VStack(alignment: .leading, spacing: ElectionDetailLayout.sourceSpacing) {
			Text("Source")
				.font(.caption.weight(.semibold))
				.foregroundStyle(.secondary)
			if let actURL = URL(string: "https://laws-lois.justice.gc.ca/eng/acts/e-2.01/section-56.1.html") {
				Link("Canada Elections Act, s.56.1", destination: actURL)
					.font(.caption)
			}
			if let ecURL = URL(string: "https://www.elections.ca") {
				Link("Elections Canada — elections.ca", destination: ecURL)
					.font(.caption)
			}
		}
		.padding(.top, ElectionDetailLayout.sourceTopPadding)
	}

	private var daysRemainingText: String {
		switch daysRemaining {
		case 0:        return "Election day"
		case 1:        return "1 day away"
		default:       return "\(daysRemaining) days away"
		}
	}
}

#Preview {
	NavigationStack {
		ElectionDetailView(
			lastElectionDate: ElectionDateCalculator.last45thGeneralElection,
			mandatedDate: ElectionDateCalculator.nextMandatedDate(after: ElectionDateCalculator.last45thGeneralElection),
			daysRemaining: 1265
		)
	}
}
