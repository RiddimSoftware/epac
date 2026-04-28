//
//  VeteransAffairsStatistics.swift
//  epac
//

import Foundation

struct VeteransAffairsSource: Decodable {
	let title: String
	let url: URL
	let note: String
}

struct VeteransAffairsAnnualStatistic: Decodable, Identifiable {
	var id: String { fiscalYear }

	let fiscalYear: String
	let disabilityPensionRecipients: Int?
	let painAndSufferingCompensationRecipients: Int?
	let additionalPainAndSufferingCompensationRecipients: Int?
	let disabilityPensionExpendituresMillions: Double?
	let painAndSufferingCompensationExpendituresMillions: Double?
	let additionalPainAndSufferingCompensationExpendituresMillions: Double?
	let benefitsServicesSupportSpendingDollars: Int?
	let serviceStandardMetPercent: Double?
	let firstApplicationAverageWeeks: Double?
	let isForecast: Bool

	enum CodingKeys: String, CodingKey {
		case fiscalYear = "fiscal_year"
		case disabilityPensionRecipients = "disability_pension_recipients"
		case painAndSufferingCompensationRecipients = "pain_and_suffering_compensation_recipients"
		case additionalPainAndSufferingCompensationRecipients = "additional_pain_and_suffering_compensation_recipients"
		case disabilityPensionExpendituresMillions = "disability_pension_expenditures_millions"
		case painAndSufferingCompensationExpendituresMillions = "pain_and_suffering_compensation_expenditures_millions"
		case additionalPainAndSufferingCompensationExpendituresMillions = "additional_pain_and_suffering_compensation_expenditures_millions"
		case benefitsServicesSupportSpendingDollars = "benefits_services_support_spending_dollars"
		case serviceStandardMetPercent = "service_standard_met_percent"
		case firstApplicationAverageWeeks = "first_application_average_weeks"
		case isForecast = "is_forecast"
	}
}

struct VeteransAffairsProvinceStatistic: Decodable, Identifiable {
	var id: String { provinceCode }

	let province: String
	let provinceCode: String
	let censusVeterans: Int
	let estimatedWarServiceVeterans: Int?

	enum CodingKeys: String, CodingKey {
		case province
		case provinceCode = "province_code"
		case censusVeterans = "census_veterans"
		case estimatedWarServiceVeterans = "estimated_war_service_veterans"
	}
}

struct VeteransAffairsNationalSummary: Decodable {
	let referenceDate: String
	let disabilityBenefitRecipients: Int
	let disabilityBenefitExpendituresDollars: Int
	let backlogApplications: Int
	let pendingApplications: Int
	let firstApplicationAverageWeeks: Double
	let firstApplicationMedianWeeks: Double

	enum CodingKeys: String, CodingKey {
		case referenceDate = "reference_date"
		case disabilityBenefitRecipients = "disability_benefit_recipients"
		case disabilityBenefitExpendituresDollars = "disability_benefit_expenditures_dollars"
		case backlogApplications = "backlog_applications"
		case pendingApplications = "pending_applications"
		case firstApplicationAverageWeeks = "first_application_average_weeks"
		case firstApplicationMedianWeeks = "first_application_median_weeks"
	}
}

struct VeteransAffairsSnapshot: Decodable {
	let source: VeteransAffairsSource
	let nationalSummary: VeteransAffairsNationalSummary
	let annual: [VeteransAffairsAnnualStatistic]
	let provinces: [VeteransAffairsProvinceStatistic]

	enum CodingKeys: String, CodingKey {
		case source
		case nationalSummary = "national_summary"
		case annual
		case provinces
	}
}

enum VeteransAffairsStatisticsDatabase {
	private static let resourceName = "vac-statistics"
	private static let mainSnapshot = loadSnapshot(bundle: .main)

	static let fallbackSource = VeteransAffairsSource(
		title: "Veterans Affairs Canada - Facts and Figures / Departmental Results Reports",
		url: URL(string: "https://www.veterans.gc.ca/en/news-and-media/facts-and-figures")!,
		note: "Provincial Veteran population comes from the 2021 Census; benefit recipients, spending, and processing times are national VAC figures."
	)

	static func snapshot(bundle: Bundle = .main) -> VeteransAffairsSnapshot? {
		if bundle === Bundle.main {
			return mainSnapshot
		}
		return loadSnapshot(bundle: bundle)
	}

	private static func loadSnapshot(bundle: Bundle) -> VeteransAffairsSnapshot? {
		guard let url = bundle.url(forResource: resourceName, withExtension: "json"),
		      let data = try? Data(contentsOf: url) else {
			return nil
		}
		return try? decode(data: data)
	}

	static func statistic(for provinceCode: String, bundle: Bundle = .main) -> VeteransAffairsProvinceStatistic? {
		snapshot(bundle: bundle)?
			.provinces
			.first { $0.provinceCode.caseInsensitiveCompare(provinceCode) == .orderedSame }
	}

	static func nationalSummary(bundle: Bundle = .main) -> VeteransAffairsNationalSummary? {
		snapshot(bundle: bundle)?.nationalSummary
	}

	static func latestAnnual(bundle: Bundle = .main) -> VeteransAffairsAnnualStatistic? {
		snapshot(bundle: bundle)?.annual.last
	}

	static func decode(data: Data) throws -> VeteransAffairsSnapshot {
		try JSONDecoder().decode(VeteransAffairsSnapshot.self, from: data)
	}

	static func dateLabel(_ isoDate: String) -> String {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_CA")
		formatter.dateFormat = "yyyy-MM-dd"
		guard let date = formatter.date(from: isoDate) else {
			return isoDate
		}
		return date.formatted(.dateTime.month(.wide).day().year())
	}
}
