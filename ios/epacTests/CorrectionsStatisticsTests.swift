@testable import epac
import Foundation
import Testing

struct CorrectionsStatisticsTests {
    @Test func decodesCorrectionsSnapshot() throws {
        let json = """
        {
          "reference_fiscal_year": "2023 to 2024",
          "source": {
            "title": "CSC Departmental Results Report and Indigenous Corrections Accountability Framework",
            "url": "https://www.canada.ca/en/correctional-service/corporate/transparency/reporting/departmental-results-reports/2023-2024.html",
            "note": "Federal corrections statistics are published annually."
          },
          "sources": [],
          "indigenous_population_share": {
            "year": "2021",
            "population": 1807250,
            "percent_of_canada": 5.0,
            "source_title": "Statistics Canada 2021 Census Profile",
            "source_url": "https://www12.statcan.gc.ca/census-recensement/2021/dp-pd/prof/details/page.cfm?DGUIDlist=2021A000011124"
          },
          "annual_statistics": [
            {
              "fiscal_year": "2023 to 2024",
              "total_in_custody": 13855,
              "indigenous_in_custody": 4579,
              "indigenous_in_custody_percent": 33.0,
              "non_indigenous_in_custody": 9276,
              "not_readmitted_five_years_percent": 89.9,
              "recidivism_rate_percent": 10.1,
              "care_and_custody_spending": 2119199375,
              "cost_per_inmate": 152956
            }
          ],
          "oci_highlights": [
            {
              "title": "Mental health services",
              "summary": "OCI highlights gaps in culturally informed services.",
              "source_url": "https://oci-bec.gc.ca/en/content/office-correctional-investigator-annual-report-2024-25"
            }
          ]
        }
        """

        let snapshot = try CorrectionsStatisticsDatabase.decode(data: Data(json.utf8))
        let latest = try #require(snapshot.latestAnnualStatistic)

        #expect(snapshot.referenceFiscalYear == "2023 to 2024")
        #expect(snapshot.indigenousPopulationShare.percentOfCanada == 5.0)
        #expect(latest.totalInCustody == 13855)
        #expect(latest.indigenousInCustodyPercent == 33.0)
        #expect(snapshot.ociHighlights.first?.title == "Mental health services")
    }

    @Test func loadsBundledSnapshot() throws {
        let snapshot = try #require(CorrectionsStatisticsDatabase.snapshot())
        let latest = try #require(snapshot.latestAnnualStatistic)

        #expect(snapshot.referenceFiscalYear == "2023 to 2024")
        #expect(snapshot.annualStatistics.count == 3)
        #expect(snapshot.indigenousPopulationShare.percentOfCanada == 5.0)
        #expect(latest.indigenousInCustody == 4579)
        #expect(latest.costPerInmate == 152956)
        #expect(CorrectionsStatisticsDatabase.sources().contains { $0.title.contains("Office of the Correctional Investigator") })
    }

    @Test func formatsFiscalYearLabel() {
        #expect(CorrectionsStatisticsDatabase.fiscalYearLabel("2023 to 2024") == "2023-2024")
    }
}
