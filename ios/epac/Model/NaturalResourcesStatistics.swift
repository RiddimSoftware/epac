//
//  NaturalResourcesStatistics.swift
//  epac
//

import Foundation

struct NaturalResourcesSource: Decodable {
	let title: String
	let url: URL
	let note: String
}

struct MineralYearStatistic: Decodable, Identifiable {
	var id: Int { year }

	let year: Int
	let shipmentValueThousands: Int?
	let isConfidential: Bool
	let isProvisional: Bool

	enum CodingKeys: String, CodingKey {
		case year
		case shipmentValueThousands = "shipment_value_thousands"
		case isConfidential = "is_confidential"
		case isProvisional = "is_provisional"
	}
}

struct MineralCommodityValue: Decodable, Identifiable {
	var id: String { commodity }

	let commodity: String
	let shipmentValueThousands: Int?
	let isConfidential: Bool

	enum CodingKeys: String, CodingKey {
		case commodity
		case shipmentValueThousands = "shipment_value_thousands"
		case isConfidential = "is_confidential"
	}
}

struct ForestryYearStatistic: Decodable, Identifiable {
	var id: Int { year }

	let year: Int
	let harvestVolumeCubicMetres: Int
	let crownTimberRevenueDollars: Int?

	enum CodingKeys: String, CodingKey {
		case year
		case harvestVolumeCubicMetres = "harvest_volume_cubic_metres"
		case crownTimberRevenueDollars = "crown_timber_revenue_dollars"
	}
}

struct NaturalResourcesProvinceStatistic: Decodable, Identifiable {
	var id: String { provinceCode }

	let province: String
	let provinceCode: String
	let showMining: Bool
	let showForestry: Bool
	let miningYears: [MineralYearStatistic]
	let topMinerals: [MineralCommodityValue]
	let forestryYears: [ForestryYearStatistic]
	let resourceNote: String?

	enum CodingKeys: String, CodingKey {
		case province
		case provinceCode = "province_code"
		case showMining = "show_mining"
		case showForestry = "show_forestry"
		case miningYears = "mining_years"
		case topMinerals = "top_minerals"
		case forestryYears = "forestry_years"
		case resourceNote = "resource_note"
	}

	var latestMiningYear: MineralYearStatistic? {
		miningYears.max { $0.year < $1.year }
	}

	var latestForestryYear: ForestryYearStatistic? {
		forestryYears.max { $0.year < $1.year }
	}

	var hasResourceContext: Bool {
		(showMining && (!miningYears.isEmpty || !topMinerals.isEmpty))
			|| (showForestry && !forestryYears.isEmpty)
	}
}

struct NaturalResourcesSnapshot: Decodable {
	let generatedAt: String
	let mineralReferenceYear: Int
	let forestryReferencePeriod: String
	let source: NaturalResourcesSource
	let forestryVolumeSource: NaturalResourcesSource
	let forestryValueSource: NaturalResourcesSource
	let provinces: [NaturalResourcesProvinceStatistic]

	enum CodingKeys: String, CodingKey {
		case generatedAt = "generated_at"
		case mineralReferenceYear = "mineral_reference_year"
		case forestryReferencePeriod = "forestry_reference_period"
		case source
		case forestryVolumeSource = "forestry_volume_source"
		case forestryValueSource = "forestry_value_source"
		case provinces
	}
}

enum NaturalResourcesStatisticsDatabase {
	private static let resourceName = "natural-resources-statistics"
	private static let mainSnapshot = loadSnapshot(bundle: .main)

	static let fallbackSource = NaturalResourcesSource(
		title: "Natural Resources Canada — Canadian Minerals Yearbook 2025",
		url: URL(string: "https://mmsd.nrcan-rncan.gc.ca/prod-prod/ann-ann-eng.aspx")!,
		note: "Mineral production, forestry harvest volume, and Crown timber revenue statistics from NRCan and the National Forestry Database."
	)

	static func snapshot(bundle: Bundle = .main) -> NaturalResourcesSnapshot? {
		if bundle === Bundle.main {
			return mainSnapshot
		}
		return loadSnapshot(bundle: bundle)
	}

	private static func loadSnapshot(bundle: Bundle) -> NaturalResourcesSnapshot? {
		guard let url = bundle.url(forResource: resourceName, withExtension: "json"),
		      let data = try? Data(contentsOf: url) else {
			return nil
		}
		return try? decode(data: data)
	}

	static func statistic(for provinceCode: String, bundle: Bundle = .main) -> NaturalResourcesProvinceStatistic? {
		snapshot(bundle: bundle)?
			.provinces
			.first { $0.provinceCode.caseInsensitiveCompare(provinceCode) == .orderedSame && $0.hasResourceContext }
	}

	static func decode(data: Data) throws -> NaturalResourcesSnapshot {
		try JSONDecoder().decode(NaturalResourcesSnapshot.self, from: data)
	}
}
