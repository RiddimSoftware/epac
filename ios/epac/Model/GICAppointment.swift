//
//  GICAppointment.swift
//  epac
//

import Foundation

struct GICAppointmentsSource: Decodable {
	let title: String
	let url: URL
	let appointmentsIndexURL: URL
	let ordersInCouncilURL: URL
	let salaryRangesURL: URL

	enum CodingKeys: String, CodingKey {
		case title
		case url
		case appointmentsIndexURL = "appointments_index_url"
		case ordersInCouncilURL = "orders_in_council_url"
		case salaryRangesURL = "salary_ranges_url"
	}
}

struct GICAppointmentsCoverage: Decodable {
	let profilesScraped: Int
	let currentOrRecentRecordsFound: Int
	let recordsBundled: Int
	let note: String

	enum CodingKeys: String, CodingKey {
		case profilesScraped = "profiles_scraped"
		case currentOrRecentRecordsFound = "current_or_recent_records_found"
		case recordsBundled = "records_bundled"
		case note
	}
}

struct GICAppointmentCompensation: Decodable {
	let kind: String
	let sourceYear: String
	let label: String
	let minimum: String
	let maximum: String
	let maximumPerformanceAward: String?

	enum CodingKeys: String, CodingKey {
		case kind
		case sourceYear = "source_year"
		case label
		case minimum
		case maximum
		case maximumPerformanceAward = "maximum_performance_award"
	}

	var displayValue: String {
		switch kind {
		case "per_diem_range":
			return "\(minimum)-\(maximum) per diem"
		default:
			return "\(minimum)-\(maximum)"
		}
	}
}

struct GICOrderInCouncil: Decodable, Identifiable {
	var id: String { pcNumber }

	let pcNumber: String
	let dateMade: String
	let department: String
	let act: String
	let subject: String
	let precis: String
	let registration: String
	let attachmentURL: URL

	enum CodingKeys: String, CodingKey {
		case pcNumber = "pc_number"
		case dateMade = "date_made"
		case department
		case act
		case subject
		case precis
		case registration
		case attachmentURL = "attachment_url"
	}
}

struct GICAppointment: Decodable, Identifiable {
	let id: String
	let name: String
	let organization: String
	let organizationID: String
	let organizationCategory: String
	let responsibleMinister: String
	let position: String
	let classificationLevel: String?
	let appointmentType: String?
	let tenure: String?
	let currentAppointmentDate: String
	let expiryDate: String?
	let profileURL: URL
	let compensation: GICAppointmentCompensation?
	let orderInCouncil: GICOrderInCouncil?

	enum CodingKeys: String, CodingKey {
		case id
		case name
		case organization
		case organizationID = "organization_id"
		case organizationCategory = "organization_category"
		case responsibleMinister = "responsible_minister"
		case position
		case classificationLevel = "classification_level"
		case appointmentType = "appointment_type"
		case tenure
		case currentAppointmentDate = "current_appointment_date"
		case expiryDate = "expiry_date"
		case profileURL = "profile_url"
		case compensation
		case orderInCouncil = "order_in_council"
	}

	var displayName: String {
		let parts = name.split(separator: ",", maxSplits: 1).map {
			$0.trimmingCharacters(in: .whitespacesAndNewlines)
		}
		guard parts.count == 2 else { return name }
		return "\(parts[1]) \(parts[0])"
	}

	var appointmentDate: Date? {
		GICAppointmentsDatabase.dateFormatter.date(from: currentAppointmentDate)
	}

	var expiry: Date? {
		guard let expiryDate else { return nil }
		return GICAppointmentsDatabase.dateFormatter.date(from: expiryDate)
	}

	func isCurrent(referenceDate: Date = Date()) -> Bool {
		if let appointmentDate, appointmentDate > referenceDate {
			return false
		}
		guard let expiry else { return true }
		return expiry >= Calendar.current.startOfDay(for: referenceDate)
	}

	var searchableText: String {
		[
			name,
			displayName,
			organization,
			organizationID,
			position,
			responsibleMinister,
			orderInCouncil?.pcNumber,
			orderInCouncil?.subject
		]
		.compactMap { $0 }
		.joined(separator: " ")
	}
}

struct GICAppointmentsSnapshot: Decodable {
	let generatedAt: String
	let retrievedAt: String
	let source: GICAppointmentsSource
	let coverage: GICAppointmentsCoverage
	let appointments: [GICAppointment]

	enum CodingKeys: String, CodingKey {
		case generatedAt = "generated_at"
		case retrievedAt = "retrieved_at"
		case source
		case coverage
		case appointments
	}
}

enum GICAppointmentStatusFilter: String, CaseIterable, Identifiable {
	case all
	case current
	case past

	var id: String { rawValue }

	var title: String {
		switch self {
		case .all: return "All"
		case .current: return "Current"
		case .past: return "Past"
		}
	}
}

enum GICAppointmentsDatabase {
	static let dateFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.calendar = Calendar(identifier: .gregorian)
		formatter.locale = Locale(identifier: "en_CA_POSIX")
		formatter.dateFormat = "yyyy-MM-dd"
		return formatter
	}()

	static let fallbackSource = GICAppointmentsSource(
		title: "Federal Organizations — Governor in Council appointees",
		url: URL(string: "https://federal-organizations.canada.ca/")!,
		appointmentsIndexURL: URL(string: "https://federal-organizations.canada.ca/gindex.php?t=3&GicGuideFlg=1&lang=en")!,
		ordersInCouncilURL: URL(string: "https://orders-in-council.canada.ca/")!,
		salaryRangesURL: URL(string: "https://www.canada.ca/en/privy-council/programs/appointments/governor-council-appointments/compensation-terms-conditions-employment/salary-ranges-performance-pay.html")!
	)

	private static let resourceName = "gic-appointments"
	private static let mainSnapshot = loadSnapshot(bundle: .main)

	static func snapshot(bundle: Bundle = .main) -> GICAppointmentsSnapshot? {
		if bundle === Bundle.main {
			return mainSnapshot
		}
		return loadSnapshot(bundle: bundle)
	}

	static func organizations(bundle: Bundle = .main) -> [String] {
		let names = snapshot(bundle: bundle)?.appointments.map(\.organization) ?? []
		return Array(Set(names)).sorted()
	}

	static func filteredAppointments(
		searchText: String,
		organization: String?,
		status: GICAppointmentStatusFilter,
		referenceDate: Date = Date(),
		bundle: Bundle = .main
	) -> [GICAppointment] {
		let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
		return (snapshot(bundle: bundle)?.appointments ?? [])
			.filter { appointment in
				(organization == nil || appointment.organization == organization)
					&& statusMatches(appointment, status: status, referenceDate: referenceDate)
					&& (query.isEmpty || appointment.searchableText.localizedCaseInsensitiveContains(query))
			}
			.sorted { left, right in
				left.currentAppointmentDate > right.currentAppointmentDate
			}
	}

	static func decode(data: Data) throws -> GICAppointmentsSnapshot {
		try JSONDecoder().decode(GICAppointmentsSnapshot.self, from: data)
	}

	private static func loadSnapshot(bundle: Bundle) -> GICAppointmentsSnapshot? {
		guard let url = bundle.url(forResource: resourceName, withExtension: "json"),
		      let data = try? Data(contentsOf: url) else {
			return nil
		}
		return try? decode(data: data)
	}

	private static func statusMatches(
		_ appointment: GICAppointment,
		status: GICAppointmentStatusFilter,
		referenceDate: Date
	) -> Bool {
		switch status {
		case .all:
			return true
		case .current:
			return appointment.isCurrent(referenceDate: referenceDate)
		case .past:
			return !appointment.isCurrent(referenceDate: referenceDate)
		}
	}
}
