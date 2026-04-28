@testable import epac
import Foundation
import Testing

struct EmploymentInsuranceStatisticsTests {
    @Test func decodesProvinceSnapshot() throws {
        let json = """
        {
          "reference_month": "2026-02",
          "source": {
            "title": "Employment and Social Development Canada — EI Statistics",
            "url": "https://www.canada.ca/en/employment-social-development/programs/ei/statistics.html",
            "note": "Monthly Statistics Canada EI tables are produced from Service Canada and ESDC administrative data."
          },
          "provinces": [
            {
              "province": "Ontario",
              "province_code": "ON",
              "reference_month": "2026-02",
              "beneficiaries": 190720,
              "claims_received": 81300,
              "claims_received_previous_year": 73510,
              "claims_year_over_year_change_percent": 10.6,
              "average_weekly_benefit": 571.58,
              "months": [
                {
                  "ref_date": "2026-02",
                  "beneficiaries": 190720,
                  "claims_received": 81300,
                  "average_weekly_benefit": 571.58
                }
              ]
            }
          ]
        }
        """

        let snapshot = try EmploymentInsuranceStatisticsDatabase.decode(data: Data(json.utf8))

        #expect(snapshot.referenceMonth == "2026-02")
        #expect(snapshot.source.title == "Employment and Social Development Canada — EI Statistics")
        #expect(snapshot.provinces.first?.provinceCode == "ON")
        #expect(snapshot.provinces.first?.claimsYearOverYearChangePercent == 10.6)
        #expect(snapshot.provinces.first?.months.first?.averageWeeklyBenefit == 571.58)
    }

    @Test func formatsReferenceMonthLabel() {
        #expect(EmploymentInsuranceStatisticsDatabase.monthLabel("2026-02") == "February 2026")
        #expect(EmploymentInsuranceStatisticsDatabase.monthLabel("bad-date") == "bad-date")
    }
}
