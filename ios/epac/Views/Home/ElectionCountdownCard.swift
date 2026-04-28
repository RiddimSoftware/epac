//
//  ElectionCountdownCard.swift
//  epac
//

import SwiftUI

// Compact countdown card surfacing the next mandated federal election.
//
// Displays the statutory date (Canada Elections Act s.56.1) and a
// day-counter that updates whenever the view re-renders. Once the
// writ-issuance pipeline ships, the card will swap to the actual writ
// date — for now it always shows the mandated date.
struct ElectionCountdownCard: View {
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
		HStack(alignment: .center, spacing: EpacSpacing.m) {
			Image(systemName: "checkmark.seal.fill")
				.font(.title2)
				.foregroundStyle(Color.epacBrand.accent)
				.accessibilityHidden(true)
			VStack(alignment: .leading, spacing: 2) {
				Text("Next federal election")
					.font(.epacSubheadline.weight(.semibold))
					.foregroundStyle(Color.epacText.primary)
				Text(Self.dateFormatter.string(from: mandatedDate))
					.font(.epacCallout)
					.foregroundStyle(Color.epacText.primary)
				Text(daysRemainingText)
					.font(.epacCaption)
					.foregroundStyle(.secondary)
			}
			Spacer()
			Image(systemName: "chevron.right")
				.font(.caption)
				.foregroundStyle(.tertiary)
		}
		.padding(.vertical, EpacSpacing.xs)
		.contentShape(Rectangle())
		.accessibilityElement(children: .combine)
		.accessibilityLabel(accessibilityLabel)
		.accessibilityIdentifier("home-election-countdown-card")
	}

	private var daysRemainingText: String {
		switch daysRemaining {
		case 0:        return "Election day"
		case 1:        return "1 day away"
		default:       return "\(daysRemaining) days away"
		}
	}

	private var accessibilityLabel: String {
		"Next federal election: \(Self.dateFormatter.string(from: mandatedDate)). \(daysRemainingText)."
	}
}

#Preview {
	ElectionCountdownCard(
		mandatedDate: ElectionDateCalculator.nextMandatedDate(after: ElectionDateCalculator.last45thGeneralElection),
		daysRemaining: 1265
	)
	.padding()
}
