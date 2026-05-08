@testable import epac
import Foundation
import Testing

struct NaturalResourcesStatisticsTests {
	@Test func decodesSnapshot() throws {
		let json = """
		{
		  "generated_at": "2026-04-28T23:35:00Z",
		  "mineral_reference_year": 2025,
		  "forestry_reference_period": "2015-2019",
		  "source": {
		    "title": "Natural Resources Canada — Canadian Minerals Yearbook 2025",
		    "url": "https://mmsd.nrcan-rncan.gc.ca/prod-prod/ann-ann-eng.aspx",
		    "note": "Mineral production."
		  },
		  "forestry_volume_source": {
		    "title": "National Forestry Database — Volume",
		    "url": "https://open.canada.ca/data/en/dataset/4148438c-1722-4c3b-a5fd-b64b5b8c768a",
		    "note": "Volume."
		  },
		  "forestry_value_source": {
		    "title": "National Forestry Database — Revenue",
		    "url": "https://open.canada.ca/data/en/dataset/e0da8068-6f08-453f-9684-7d00cd6f6f93",
		    "note": "Revenue."
		  },
		  "provinces": [
		    {
		      "province": "Saskatchewan",
		      "province_code": "SK",
		      "show_mining": true,
		      "show_forestry": false,
		      "mining_years": [
		        {
		          "year": 2025,
		          "shipment_value_thousands": null,
		          "is_confidential": true,
		          "is_provisional": true
		        }
		      ],
		      "top_minerals": [
		        {
		          "commodity": "Potash (muriate of potash)",
		          "shipment_value_thousands": 9493680,
		          "is_confidential": false
		        }
		      ],
		      "forestry_years": [],
		      "resource_note": "Potash is Saskatchewan's top visible mineral shipment value."
		    }
		  ]
		}
		"""

		let snapshot = try NaturalResourcesStatisticsDatabase.decode(data: Data(json.utf8))
		let saskatchewan = try #require(snapshot.provinces.first)

		#expect(snapshot.mineralReferenceYear == 2025)
		#expect(saskatchewan.latestMiningYear?.isConfidential == true)
		#expect(saskatchewan.topMinerals.first?.commodity.contains("Potash") == true)
		#expect(saskatchewan.hasResourceContext)
	}

	@Test func loadsBundledSnapshot() throws {
		let snapshot = try #require(NaturalResourcesStatisticsDatabase.snapshot())

		#expect(snapshot.source.title == "Natural Resources Canada — Canadian Minerals Yearbook 2025")
		#expect(snapshot.provinces.count == 7)
		#expect(NaturalResourcesStatisticsDatabase.statistic(for: "ON")?.showMining == true)
		#expect(NaturalResourcesStatisticsDatabase.statistic(for: "ON")?.showForestry == true)
		#expect(NaturalResourcesStatisticsDatabase.statistic(for: "NB")?.showMining == false)
		#expect(NaturalResourcesStatisticsDatabase.statistic(for: "SK")?.topMinerals.first?.commodity.contains("Potash") == true)
		#expect(NaturalResourcesStatisticsDatabase.statistic(for: "AB") == nil)
		#expect(NaturalResourcesStatisticsDatabase.statistic(for: "BC")?.latestForestryYear?.year == 2018)
		#expect(NaturalResourcesStatisticsDatabase.statistic(for: "MB")?.latestForestryYear?.year == 2019)
	}

	@Test func naturalResourceTopicMatchesDebateTags() {
		let forestryMatches = ParliamentaryTopic.matching("Forestry harvest and timber revenue")
		let miningMatches = ParliamentaryTopic.matching("Mining and potash exports")
		let energyMatches = ParliamentaryTopic.matching("Energy pipelines")

		#expect(forestryMatches.contains { $0.id == "naturalresources" })
		#expect(miningMatches.contains { $0.id == "naturalresources" })
		#expect(energyMatches.contains { $0.id == "energy" })
	}

	@Test func expandedTopicKeywordsRemainCanonical() {
		let defenceMatches = ParliamentaryTopic.matching("Veterans Affairs and NATO readiness")
		let justiceMatches = ParliamentaryTopic.matching("Parole reform and correctional policy")

		#expect(defenceMatches.contains { $0.id == "defence" })
		#expect(justiceMatches.contains { $0.id == "justice" })
	}
}
