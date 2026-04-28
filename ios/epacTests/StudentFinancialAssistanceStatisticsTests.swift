@testable import epac
import Foundation
import Testing

struct StudentFinancialAssistanceStatisticsTests {
    @Test func decodesProvinceSnapshot() throws {
        let json = """
        {
          "reference_academic_year": "2023 to 2024",
          "tuition_reference_year": "2025/2026",
          "source": {
            "title": "ESDC CSFA Program and Statistics Canada tuition data",
            "url": "https://www.canada.ca/en/employment-social-development/programs/canada-student-loans-grants/reports/student-financial-assistance-statistics-2023-2024.html",
            "note": "Federal student assistance and tuition data are published annually."
          },
          "sources": [],
          "national_rap_recipients": [
            { "academic_year": "2023 to 2024", "rap_recipients": 288368 }
          ],
          "provinces": [
            {
              "province": "Ontario",
              "province_code": "ON",
              "csfa_participating": true,
              "tuition_years": [
                {
                  "academic_year": "2025/2026",
                  "average_undergraduate_tuition": 8958,
                  "year_over_year_change_percent": 1.6
                }
              ],
              "csfa_years": [
                {
                  "academic_year": "2023 to 2024",
                  "loan_recipients": 377860,
                  "loan_disbursements_millions": 2567.8,
                  "average_loan_amount": 6795,
                  "rap_recipients": 160576
                }
              ]
            }
          ]
        }
        """

        let snapshot = try StudentFinancialAssistanceStatisticsDatabase.decode(data: Data(json.utf8))
        let ontario = try #require(snapshot.provinces.first)

        #expect(snapshot.referenceAcademicYear == "2023 to 2024")
        #expect(snapshot.tuitionReferenceYear == "2025/2026")
        #expect(snapshot.nationalRAPRecipients.first?.rapRecipients == 288368)
        #expect(ontario.latestTuitionYear?.averageUndergraduateTuition == 8958)
        #expect(ontario.latestCSFAYear?.rapRecipients == 160576)
    }

    @Test func loadsBundledSnapshot() throws {
        let snapshot = try #require(StudentFinancialAssistanceStatisticsDatabase.snapshot())

        #expect(snapshot.referenceAcademicYear == "2023 to 2024")
        #expect(snapshot.tuitionReferenceYear == "2025/2026")
        #expect(snapshot.provinces.count == 11)
        #expect(snapshot.provinces.allSatisfy { !$0.tuitionYears.isEmpty })
        #expect(StudentFinancialAssistanceStatisticsDatabase.statistic(for: "on")?.province == "Ontario")
        #expect(StudentFinancialAssistanceStatisticsDatabase.statistic(for: "qc")?.csfaYears.isEmpty == true)
    }

    @Test func formatsAcademicYearLabel() {
        #expect(StudentFinancialAssistanceStatisticsDatabase.academicYearLabel("2025/2026") == "2025-2026")
    }
}
