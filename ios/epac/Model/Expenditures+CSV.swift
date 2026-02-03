import SwiftData
import Foundation

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
					
					if row.count < 7 {
						Log.debug("Skipping row with only \(row.count) columns: \(row.joined(separator: "|"))")
						continue
					}
					
					let nameParts = row[0].components(separatedBy: ",")
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
														 constituency: row[1],
														 caucus: row[2],
														 salaries: Double(row[3]) ?? 0.0,
														 travel: Double(row[4]) ?? 0.0,
														 hospitality: Double(row[5]) ?? 0.0,
														 contracts: Double(row[6]) ?? 0.0,
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

extension TravelClaim {
	static func fromCSV(_ parser: CSVParser) -> AsyncStream<TravelClaimData> {
		return AsyncStream { continuation in
			Task {
				var claims: [String: TravelClaimData] = [:]
				
				var headerCount = 2
				var isNewSchema = false
				var rowCount = 0
				for await row in parser.parse() {
					if headerCount == 1 {
						if row.contains("Places Visited") {
							isNewSchema = true
						}
						headerCount -= 1
						continue
					}
					if headerCount > 0 { headerCount -= 1; continue }
					if row.isEmpty || row.allSatisfy({ $0.isEmpty }) { continue }

					if isNewSchema {
						guard row.count >= 11 else { continue }
						let startDate = DateUtils.getDate(forCSVDateString: row[0])
						let endDate = DateUtils.getDate(forCSVDateString: row[1])
						let departure = row[2]
						let destination = row[3]
						let purpose = row[4]
						let travellerName = row[5]
						let travellerType = row[6]
						let transportation = Double(row[7]) ?? 0
						let accommodations = Double(row[8]) ?? 0
						let mealsAndIncidentals = Double(row[9]) ?? 0
						let total = Double(row[10]) ?? 0
						
						let claimID = "NS-\(rowCount)"
						rowCount += 1
						
						let detail = TravelExpenditureDetailData(
							travellerName: travellerName.isEmpty ? nil : travellerName,
							travellerType: travellerType,
							purposeOfTravel: purpose,
							date: startDate,
							departure: departure,
							destination: destination
						)
						
						claims[claimID] = TravelClaimData(
							claimID: claimID,
							startDate: startDate,
							endDate: endDate,
							transportation: transportation,
							accommodations: accommodations,
							mealsAndIncidentals: mealsAndIncidentals,
							total: total,
							details: [detail]
						)
					} else {
						guard row.count >= 16, let claimID = row.first, !claimID.isEmpty else {
							continue
						}

						let isSummaryRow = row[3].isEmpty

						if isSummaryRow {
							let startDate = DateUtils.getDate(forCSVDateString: row[1])
							let endDate = DateUtils.getDate(forCSVDateString: row[2])
							let transportation = Double(row[9]) ?? 0
							let accommodations = Double(row[10]) ?? 0
							let mealsAndIncidentals = Double(row[11]) ?? 0
							let total = Double(row[15]) ?? 0
							
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
						} else {
							let detail = TravelExpenditureDetailData(
								travellerName: row[3].isEmpty ? nil : row[3],
								travellerType: row[4],
								purposeOfTravel: row[5],
								date: DateUtils.getDate(forCSVDateString: row[6]),
								departure: row[7],
								destination: row[8]
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
					}
				}
				
				for claim in claims.values.sorted(by: { $0.startDate < $1.startDate }) {
					if claim.total != 0 {
						continuation.yield(claim)
					}
				}
				continuation.finish()
			}
		}
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

extension HospitalityExpenditure {
	static func fromCSV(_ parser: CSVParser) -> AsyncStream<HospitalityExpenditureData> {
		return AsyncStream { continuation in
			Task {
				var headerCount = 2
				var isNewSchema = false
				for await row in parser.parse() {
					if headerCount == 1 {
						if row.contains("Amount") && !row.contains("Claim") {
							isNewSchema = true
						}
						headerCount -= 1
						continue
					}
					if headerCount > 0 { headerCount -= 1; continue }
					
					if isNewSchema {
						guard row.count >= 7 else { continue }
						let item = HospitalityExpenditureData(
							date: DateUtils.getDate(forCSVDateString: row[0]),
							location: row[1],
							totalOfAttendees: Int(row[2]) ?? 0,
							purposeOfHospitality: row[3],
							total: Double(row[6]) ?? 0,
							typeOfEvent: "",
							claim: "",
							supplier: row[4]
						)
						continuation.yield(item)
					} else {
						guard row.count >= 8 else { continue }
						let item = HospitalityExpenditureData(
							date: DateUtils.getDate(forCSVDateString: row[0]),
							location: row[1],
							totalOfAttendees: Int(row[2]) ?? 0,
							purposeOfHospitality: row[3],
							total: Double(row[7]) ?? 0,
							typeOfEvent: row[4],
							claim: row[5],
							supplier: row[6]
						)
						continuation.yield(item)
					}
				}
				continuation.finish()
			}
		}
	}
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
				var headerCount = 2
				for await row in parser.parse() {
					if headerCount > 0 { headerCount -= 1; continue }
					guard row.count >= 4 else { continue }
					
					let item = ContractExpenditureData(
						supplier: row[0],
						details: row[1],
						date: DateUtils.getDate(forCSVDateString: row[2]),
						total: Double(row[3]) ?? 0
					)
					continuation.yield(item)
				}
				continuation.finish()
			}
		}
	}
}
