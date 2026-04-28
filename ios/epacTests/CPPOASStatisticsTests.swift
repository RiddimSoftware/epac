@testable import epac
import Foundation
import Testing

struct CPPOASStatisticsTests {
    @Test func decodesProvinceSnapshot() throws {
        let json = """
        {
          "history_years": [2023, 2024, 2025],
          "source": {
            "title": "Employment and Social Development Canada — CPP/OAS Statistical Bulletin",
            "url": "https://www.canada.ca/en/employment-social-development/programs/pensions/reports/statistical-bulletin.html",
            "note": "Provincial recipient counts from ESDC."
          },
          "provinces": [
            {
              "province": "Ontario",
              "province_code": "ON",
              "cpp_retirement_recipients": 2985163,
              "cpp_reference_period": "2026-04",
              "oas_pension_recipients": 2774278,
              "oas_reference_period": "2025-03",
              "history": [
                {"year": 2023, "cpp_retirement_recipients": 2805015, "oas_pension_recipients": 2661484},
                {"year": 2024, "cpp_retirement_recipients": 2878197, "oas_pension_recipients": 2754575},
                {"year": 2025, "cpp_retirement_recipients": 2957421, "oas_pension_recipients": 2774278}
              ]
            }
          ],
          "national": {
            "cpp_retirement_recipients": 6119362,
            "cpp_reference_period": "2026-04",
            "oas_pension_recipients": 7418908,
            "oas_reference_period": "2025-03"
          }
        }
        """

        let snapshot = try CPPOASStatisticsDatabase.decode(data: Data(json.utf8))

        #expect(snapshot.historyYears == [2023, 2024, 2025])
        #expect(snapshot.source.title.contains("CPP/OAS"))
        #expect(snapshot.provinces.first?.provinceCode == "ON")
        #expect(snapshot.provinces.first?.cppRetirementRecipients == 2_985_163)
        #expect(snapshot.provinces.first?.oasPensionRecipients == 2_774_278)
        #expect(snapshot.provinces.first?.history.count == 3)
        #expect(snapshot.national.cppRetirementRecipients == 6_119_362)
        #expect(snapshot.national.oasPensionRecipients == 7_418_908)
    }

    @Test func formatsPeriodLabel() {
        #expect(CPPOASStatisticsDatabase.periodLabel("2026-04") == "April 2026")
        #expect(CPPOASStatisticsDatabase.periodLabel("2025-03") == "March 2025")
        #expect(CPPOASStatisticsDatabase.periodLabel("bad") == "bad")
    }

    @Test func loadsBundledSnapshot() throws {
        let snapshot = try #require(CPPOASStatisticsDatabase.snapshot())

        #expect(snapshot.provinces.count == 13)
        #expect(snapshot.historyYears.count == 3)
        #expect(snapshot.provinces.allSatisfy { $0.history.count == 3 })
        let on = CPPOASStatisticsDatabase.statistic(for: "on")
        #expect(on?.province == "Ontario")
        let national = CPPOASStatisticsDatabase.national()
        #expect((national?.cppRetirementRecipients ?? 0) > 1_000_000)
        #expect((national?.oasPensionRecipients ?? 0) > 1_000_000)
    }
}
