@testable import epac
import Foundation
import Testing

struct VeteransAffairsStatisticsTests {
	@Test func decodesSnapshot() throws {
		let json = """
		{
		  "source": {
		    "title": "Veterans Affairs Canada - Facts and Figures / Departmental Results Reports",
		    "url": "https://www.veterans.gc.ca/en/news-and-media/facts-and-figures",
		    "note": "National and provincial VAC statistics."
		  },
		  "national_summary": {
		    "reference_date": "2024-03-31",
		    "disability_benefit_recipients": 144174,
		    "disability_benefit_expenditures_dollars": 2400000000,
		    "backlog_applications": 5637,
		    "pending_applications": 35265,
		    "first_application_average_weeks": 18.8,
		    "first_application_median_weeks": 11.3
		  },
		  "annual": [
		    {
		      "fiscal_year": "2023-24",
		      "disability_pension_recipients": null,
		      "pain_and_suffering_compensation_recipients": null,
		      "additional_pain_and_suffering_compensation_recipients": null,
		      "disability_pension_expenditures_millions": null,
		      "pain_and_suffering_compensation_expenditures_millions": null,
		      "additional_pain_and_suffering_compensation_expenditures_millions": null,
		      "benefits_services_support_spending_dollars": 5838792540,
		      "service_standard_met_percent": 69,
		      "first_application_average_weeks": 18.8,
		      "is_forecast": false
		    }
		  ],
		  "provinces": [
		    {
		      "province": "Ontario",
		      "province_code": "ON",
		      "census_veterans": 149020,
		      "estimated_war_service_veterans": 11000
		    }
		  ]
		}
		"""

		let snapshot = try VeteransAffairsStatisticsDatabase.decode(data: Data(json.utf8))

		#expect(snapshot.nationalSummary.disabilityBenefitRecipients == 144_174)
		#expect(snapshot.annual.first?.benefitsServicesSupportSpendingDollars == 5_838_792_540)
		#expect(snapshot.provinces.first?.provinceCode == "ON")
		#expect(snapshot.provinces.first?.censusVeterans == 149_020)
	}

	@Test func loadsBundledSnapshot() throws {
		let snapshot = try #require(VeteransAffairsStatisticsDatabase.snapshot())

		#expect(snapshot.provinces.count == 10)
		#expect(snapshot.annual.count >= 3)
		#expect(snapshot.nationalSummary.backlogApplications > 0)
		#expect(VeteransAffairsStatisticsDatabase.statistic(for: "on")?.province == "Ontario")
		#expect(VeteransAffairsStatisticsDatabase.nationalSummary()?.firstApplicationAverageWeeks == 18.8)
		#expect(VeteransAffairsStatisticsDatabase.latestAnnual()?.fiscalYear == "2024-25")
		#expect(VeteransAffairsStatisticsDatabase.dateLabel(snapshot.nationalSummary.referenceDate) == "March 31, 2024")
	}
}
