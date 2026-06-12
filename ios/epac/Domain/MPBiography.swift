//
//  MPBiography.swift
//  epac
//

import Foundation

struct MemberBiography: Equatable, Sendable {
	let yearsServed: [ParliamentaryServicePeriod]
	let previousRoles: [ParliamentaryRole]
	let education: [String]
	let professionalBackground: [String]
	let sponsoredBills: [SponsoredBillReference]
	let sourceURL: URL?
	let officialProfileURL: URL?

	var hasDisplayContent: Bool {
		!yearsServed.isEmpty ||
			!previousRoles.isEmpty ||
			!education.isEmpty ||
			!professionalBackground.isEmpty ||
			!sponsoredBills.isEmpty
	}

	func withFallbackServicePeriod(_ period: ParliamentaryServicePeriod?) -> MemberBiography {
		guard yearsServed.isEmpty, let period else { return self }
		return MemberBiography(
			yearsServed: [period],
			previousRoles: previousRoles,
			education: education,
			professionalBackground: professionalBackground,
			sponsoredBills: sponsoredBills,
			sourceURL: sourceURL,
			officialProfileURL: officialProfileURL
		)
	}
}

struct ParliamentaryServicePeriod: Equatable, Sendable, Identifiable {
	let id: String
	let label: String
	let fromDate: String?
	let toDate: String?

	var displayText: String {
		let range = [fromDate, toDate ?? "Present"]
			.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
			.filter { !$0.isEmpty }
			.joined(separator: " - ")
		if label.isEmpty { return range }
		if range.isEmpty { return label }
		return "\(label): \(range)"
	}
}

struct ParliamentaryRole: Equatable, Sendable, Identifiable {
	let id: String
	let title: String
	let organization: String?
	let startDate: String?
	let endDate: String?

	var displayText: String {
		var text = title
		if let organization, !organization.isEmpty {
			text += ", \(organization)"
		}
		let range = [startDate, endDate]
			.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
			.filter { !$0.isEmpty }
			.joined(separator: " - ")
		if !range.isEmpty {
			text += " (\(range))"
		}
		return text
	}
}

struct SponsoredBillReference: Equatable, Sendable, Identifiable {
	let id: String
	let number: String
	let title: String
	let relationship: String
	let legisInfoURL: URL?

	var displayTitle: String {
		title.isEmpty ? number : "\(number) - \(title)"
	}
}
