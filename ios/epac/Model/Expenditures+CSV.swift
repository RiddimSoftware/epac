import Foundation
import SwiftData

private enum SummaryExpenditureCSVColumn {
	static let minimumCount = 7
	static let fullName = 0
	static let constituency = 1
	static let caucus = 2
	static let salaries = 3
	static let travel = 4
	static let hospitality = 5
	static let contracts = 6
}

private enum TravelCSVColumn {
	static let headerRowCount = 2
	static let schemaHeaderRemainingCount = 1

	static let placesVisitedMinimumCount = 11
	static let placesVisitedStartDate = 0
	static let placesVisitedEndDate = 1
	static let placesVisitedDeparture = 2
	static let placesVisitedDestination = 3
	static let placesVisitedPurpose = 4
	static let placesVisitedTravellerName = 5
	static let placesVisitedTravellerType = 6
	static let placesVisitedTransportation = 7
	static let placesVisitedAccommodations = 8
	static let placesVisitedMealsAndIncidentals = 9
	static let placesVisitedTotal = 10

	static let legacyMinimumCount = 16
	static let legacyStartDate = 1
	static let legacyEndDate = 2
	static let legacySummaryMarker = 3
	static let legacyTravellerName = 3
	static let legacyTravellerType = 4
	static let legacyPurpose = 5
	static let legacyDetailDate = 6
	static let legacyDeparture = 7
	static let legacyDestination = 8
	static let legacyTransportation = 9
	static let legacyAccommodations = 10
	static let legacyMealsAndIncidentals = 11
	static let legacyTotal = 15
}

private enum HospitalityCSVColumn {
	static let headerRowCount = 2
	static let schemaHeaderRemainingCount = 1

	static let amountOnlyMinimumCount = 7
	static let legacyMinimumCount = 8
	static let date = 0
	static let location = 1
	static let totalOfAttendees = 2
	static let purpose = 3
	static let amountOnlySupplier = 4
	static let amountOnlyTotal = 6
	static let legacyTypeOfEvent = 4
	static let legacyClaim = 5
	static let legacySupplier = 6
	static let legacyTotal = 7
}

private enum ContractCSVColumn {
	static let headerRowCount = 2
	static let minimumCount = 4
	static let supplier = 0
	static let details = 1
	static let date = 2
	static let total = 3
}

extension SummaryExpenditure {
	static func fromCSV(_ parser: CSVParser, year: Int, quarter: Int) -> AsyncStream<SummaryExpenditure> {
		return AsyncStream { continuation in
			Task {
				var isHeader = true
				for await row in parser.parse() {
					if isHeader {
						Log.debug("CSV Header: \(row.joined(separator: "|"))")
						isHeader = false
						continue
					}
					
					if row.count < SummaryExpenditureCSVColumn.minimumCount {
						Log.debug("Skipping row with only \(row.count) columns: \(row.joined(separator: "|"))")
						continue
					}
					
					let nameParts = row[SummaryExpenditureCSVColumn.fullName].components(separatedBy: ",")
					let lastName = nameParts.first?.trimmingCharacters(in: .whitespaces) ?? ""
					var firstName = nameParts.count > 1 ? nameParts[1].trimmingCharacters(in: .whitespaces) : ""
					
					let titles = ["Right Hon.", "Hon."]
					for title in titles {
						if firstName.hasPrefix(title) {
							firstName = firstName.replacingOccurrences(of: title, with: "").trimmingCharacters(in: .whitespaces)
							break
						}
					}
					
					let expenditure = SummaryExpenditure(firstName: firstName,
														 lastName: lastName,
														 constituency: row[SummaryExpenditureCSVColumn.constituency],
														 caucus: row[SummaryExpenditureCSVColumn.caucus],
														 salaries: Double(row[SummaryExpenditureCSVColumn.salaries]) ?? 0.0,
														 travel: Double(row[SummaryExpenditureCSVColumn.travel]) ?? 0.0,
														 hospitality: Double(row[SummaryExpenditureCSVColumn.hospitality]) ?? 0.0,
														 contracts: Double(row[SummaryExpenditureCSVColumn.contracts]) ?? 0.0,
														 year: year,
														 quarter: quarter,
														 travelURL: nil,
														 hospitalityURL: nil,
														 contractsURL: nil)
					continuation.yield(expenditure)
				}
				continuation.finish()
			}
		}
	}
}

struct TravelClaimData: Sendable {
    var claimID: String
    var startDate: Date
    var endDate: Date
    var transportation: Double
    var accommodations: Double
    var mealsAndIncidentals: Double
    var total: Double
    var details: [TravelExpenditureDetailData]
}

struct TravelExpenditureDetailData: Sendable {
    var travellerName: String?
    var travellerType: String
    var purposeOfTravel: String
    var date: Date
    var departure: String
    var destination: String
}

private enum TravelCSVSchema {
	case legacy
	case placesVisited
}

extension TravelClaim {
	static func fromCSV(_ parser: CSVParser) -> AsyncStream<TravelClaimData> {
		return AsyncStream { continuation in
			Task {
				var claims: [String: TravelClaimData] = [:]
				
				var headerCount = TravelCSVColumn.headerRowCount
				var schema = TravelCSVSchema.legacy
				var rowCount = 0
				for await row in parser.parse() {
					if consumeTravelHeader(row, headerCount: &headerCount, schema: &schema) { continue }
					if isBlankCSVRow(row) { continue }

					updateTravelClaims(&claims, with: row, schema: schema, rowCount: &rowCount)
				}
				
				yieldNonZeroTravelClaims(from: claims, to: continuation)
				continuation.finish()
			}
		}
	}
}

private func consumeTravelHeader(
	_ row: [String],
	headerCount: inout Int,
	schema: inout TravelCSVSchema
) -> Bool {
	guard headerCount > 0 else { return false }
	if headerCount == TravelCSVColumn.schemaHeaderRemainingCount {
		schema = travelSchema(fromHeader: row)
	}
	headerCount -= 1
	return true
}

private func isBlankCSVRow(_ row: [String]) -> Bool {
	row.isEmpty || row.allSatisfy(\.isEmpty)
}

private func updateTravelClaims(
	_ claims: inout [String: TravelClaimData],
	with row: [String],
	schema: TravelCSVSchema,
	rowCount: inout Int
) {
	switch schema {
	case .placesVisited:
		appendPlacesVisitedTravelClaim(to: &claims, row: row, rowCount: &rowCount)
	case .legacy:
		updateLegacyTravelClaims(&claims, with: row)
	}
}

private func appendPlacesVisitedTravelClaim(
	to claims: inout [String: TravelClaimData],
	row: [String],
	rowCount: inout Int
) {
	guard let newClaim = placesVisitedTravelClaim(from: row, rowCount: rowCount) else { return }
	claims[newClaim.claimID] = newClaim
	rowCount += 1
}

private func yieldNonZeroTravelClaims(
	from claims: [String: TravelClaimData],
	to continuation: AsyncStream<TravelClaimData>.Continuation
) {
	for claim in claims.values.sorted(by: { $0.startDate < $1.startDate }) where claim.total != 0 {
		continuation.yield(claim)
	}
}

private func travelSchema(fromHeader row: [String]) -> TravelCSVSchema {
	row.contains("Places Visited") ? .placesVisited : .legacy
}

private func placesVisitedTravelClaim(from row: [String], rowCount: Int) -> TravelClaimData? {
	guard row.count >= TravelCSVColumn.placesVisitedMinimumCount else { return nil }
	let startDate = DateUtils.getDate(forCSVDateString: row[TravelCSVColumn.placesVisitedStartDate])
	let endDate = DateUtils.getDate(forCSVDateString: row[TravelCSVColumn.placesVisitedEndDate])
	let detail = TravelExpenditureDetailData(
		travellerName: row[TravelCSVColumn.placesVisitedTravellerName].isEmpty
			? nil
			: row[TravelCSVColumn.placesVisitedTravellerName],
		travellerType: row[TravelCSVColumn.placesVisitedTravellerType],
		purposeOfTravel: row[TravelCSVColumn.placesVisitedPurpose],
		date: startDate,
		departure: row[TravelCSVColumn.placesVisitedDeparture],
		destination: row[TravelCSVColumn.placesVisitedDestination]
	)

	return TravelClaimData(
		claimID: "NS-\(rowCount)",
		startDate: startDate,
		endDate: endDate,
		transportation: Double(row[TravelCSVColumn.placesVisitedTransportation]) ?? 0,
		accommodations: Double(row[TravelCSVColumn.placesVisitedAccommodations]) ?? 0,
		mealsAndIncidentals: Double(row[TravelCSVColumn.placesVisitedMealsAndIncidentals]) ?? 0,
		total: Double(row[TravelCSVColumn.placesVisitedTotal]) ?? 0,
		details: [detail]
	)
}

private func updateLegacyTravelClaims(_ claims: inout [String: TravelClaimData], with row: [String]) {
	guard let claimID = legacyTravelClaimID(from: row) else { return }

	if isLegacyTravelSummaryRow(row) {
		updateLegacyTravelSummary(&claims, claimID: claimID, row: row)
	} else {
		appendLegacyTravelDetail(to: &claims, claimID: claimID, row: row)
	}
}

private func legacyTravelClaimID(from row: [String]) -> String? {
	guard row.count >= TravelCSVColumn.legacyMinimumCount, let claimID = row.first, !claimID.isEmpty else { return nil }
	return claimID
}

private func isLegacyTravelSummaryRow(_ row: [String]) -> Bool {
	row[TravelCSVColumn.legacySummaryMarker].isEmpty
}

private func updateLegacyTravelSummary(_ claims: inout [String: TravelClaimData], claimID: String, row: [String]) {
	let startDate = DateUtils.getDate(forCSVDateString: row[TravelCSVColumn.legacyStartDate])
	let endDate = DateUtils.getDate(forCSVDateString: row[TravelCSVColumn.legacyEndDate])
	let transportation = Double(row[TravelCSVColumn.legacyTransportation]) ?? 0
	let accommodations = Double(row[TravelCSVColumn.legacyAccommodations]) ?? 0
	let mealsAndIncidentals = Double(row[TravelCSVColumn.legacyMealsAndIncidentals]) ?? 0
	let total = Double(row[TravelCSVColumn.legacyTotal]) ?? 0

	if var existing = claims[claimID] {
		existing.startDate = startDate
		existing.endDate = endDate
		existing.transportation = transportation
		existing.accommodations = accommodations
		existing.mealsAndIncidentals = mealsAndIncidentals
		existing.total = total
		claims[claimID] = existing
	} else {
		claims[claimID] = TravelClaimData(
			claimID: claimID,
			startDate: startDate,
			endDate: endDate,
			transportation: transportation,
			accommodations: accommodations,
			mealsAndIncidentals: mealsAndIncidentals,
			total: total,
			details: []
		)
	}
}

private func appendLegacyTravelDetail(to claims: inout [String: TravelClaimData], claimID: String, row: [String]) {
	let detail = TravelExpenditureDetailData(
		travellerName: row[TravelCSVColumn.legacyTravellerName].isEmpty
			? nil
			: row[TravelCSVColumn.legacyTravellerName],
		travellerType: row[TravelCSVColumn.legacyTravellerType],
		purposeOfTravel: row[TravelCSVColumn.legacyPurpose],
		date: DateUtils.getDate(forCSVDateString: row[TravelCSVColumn.legacyDetailDate]),
		departure: row[TravelCSVColumn.legacyDeparture],
		destination: row[TravelCSVColumn.legacyDestination]
	)

	if var existing = claims[claimID] {
		existing.details.append(detail)
		claims[claimID] = existing
	} else {
		claims[claimID] = TravelClaimData(
			claimID: claimID,
			startDate: .distantPast,
			endDate: .distantPast,
			transportation: 0,
			accommodations: 0,
			mealsAndIncidentals: 0,
			total: 0,
			details: [detail]
		)
	}
}

struct HospitalityExpenditureData: Sendable {
    var date: Date
    var location: String
    var totalOfAttendees: Int
    var purposeOfHospitality: String
    var total: Double
    var typeOfEvent: String
    var claim: String
    var supplier: String
}

private enum HospitalityCSVSchema {
	case legacy
	case amountOnly
}

extension HospitalityExpenditure {
	static func fromCSV(_ parser: CSVParser) -> AsyncStream<HospitalityExpenditureData> {
		return AsyncStream { continuation in
			Task {
				var headerCount = HospitalityCSVColumn.headerRowCount
				var schema = HospitalityCSVSchema.legacy
				for await row in parser.parse() {
					if headerCount == HospitalityCSVColumn.schemaHeaderRemainingCount {
						schema = hospitalitySchema(fromHeader: row)
						headerCount -= 1
						continue
					}
					if headerCount > 0 { headerCount -= 1; continue }
					
					if let item = hospitalityExpenditure(from: row, schema: schema) {
						continuation.yield(item)
					}
				}
				continuation.finish()
			}
		}
	}
}

private func hospitalitySchema(fromHeader row: [String]) -> HospitalityCSVSchema {
	row.contains("Amount") && !row.contains("Claim") ? .amountOnly : .legacy
}

private func hospitalityExpenditure(
	from row: [String],
	schema: HospitalityCSVSchema
) -> HospitalityExpenditureData? {
	switch schema {
	case .amountOnly:
		return amountOnlyHospitalityExpenditure(from: row)
	case .legacy:
		return legacyHospitalityExpenditure(from: row)
	}
}

private func amountOnlyHospitalityExpenditure(from row: [String]) -> HospitalityExpenditureData? {
	guard row.count >= HospitalityCSVColumn.amountOnlyMinimumCount else { return nil }
	return HospitalityExpenditureData(
		date: DateUtils.getDate(forCSVDateString: row[HospitalityCSVColumn.date]),
		location: row[HospitalityCSVColumn.location],
		totalOfAttendees: Int(row[HospitalityCSVColumn.totalOfAttendees]) ?? 0,
		purposeOfHospitality: row[HospitalityCSVColumn.purpose],
		total: Double(row[HospitalityCSVColumn.amountOnlyTotal]) ?? 0,
		typeOfEvent: "",
		claim: "",
		supplier: row[HospitalityCSVColumn.amountOnlySupplier]
	)
}

private func legacyHospitalityExpenditure(from row: [String]) -> HospitalityExpenditureData? {
	guard row.count >= HospitalityCSVColumn.legacyMinimumCount else { return nil }
	return HospitalityExpenditureData(
		date: DateUtils.getDate(forCSVDateString: row[HospitalityCSVColumn.date]),
		location: row[HospitalityCSVColumn.location],
		totalOfAttendees: Int(row[HospitalityCSVColumn.totalOfAttendees]) ?? 0,
		purposeOfHospitality: row[HospitalityCSVColumn.purpose],
		total: Double(row[HospitalityCSVColumn.legacyTotal]) ?? 0,
		typeOfEvent: row[HospitalityCSVColumn.legacyTypeOfEvent],
		claim: row[HospitalityCSVColumn.legacyClaim],
		supplier: row[HospitalityCSVColumn.legacySupplier]
	)
}

struct ContractExpenditureData: Sendable {
    var supplier: String
    var details: String
    var date: Date
    var total: Double
}

extension ContractExpenditure {
	static func fromCSV(_ parser: CSVParser) -> AsyncStream<ContractExpenditureData> {
		return AsyncStream { continuation in
			Task {
				var headerCount = ContractCSVColumn.headerRowCount
				for await row in parser.parse() {
					if headerCount > 0 { headerCount -= 1; continue }
					guard row.count >= ContractCSVColumn.minimumCount else { continue }
					
					let item = ContractExpenditureData(
						supplier: row[ContractCSVColumn.supplier],
						details: row[ContractCSVColumn.details],
						date: DateUtils.getDate(forCSVDateString: row[ContractCSVColumn.date]),
						total: Double(row[ContractCSVColumn.total]) ?? 0
					)
					continuation.yield(item)
				}
				continuation.finish()
			}
		}
	}
}
