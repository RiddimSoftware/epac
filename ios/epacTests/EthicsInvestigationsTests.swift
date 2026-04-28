@testable import epac
import Foundation
import Testing

struct EthicsInvestigationsTests {
    @Test func decodesInvestigationSnapshot() throws {
        let json = """
        {
          "generated_at": "2026-04-28T00:00:00Z",
          "source": {
            "title": "Conflict of Interest and Ethics Commissioner — Investigation Reports",
            "url": "https://ciec-ccie.parl.gc.ca/en/investigations-enquetes/Pages/InvestReport-RapportEnquete.aspx",
            "note": "Contains reports under the Act and Code."
          },
          "investigations": [
            {
              "subject_last_name": "Fergus",
              "subject_full_name": "Greg Fergus",
              "report_title": "Fergus Report",
              "date": "2023-02-14",
              "type": "Act",
              "page_url": "https://ciec-ccie.parl.gc.ca/en/investigations-enquetes/Pages/FergusReport-RapportFergus.aspx"
            },
            {
              "subject_last_name": "Ratansi",
              "subject_full_name": "Yasmin Ratansi",
              "report_title": "Ratansi Report",
              "date": "2021-06-15",
              "type": "Code",
              "page_url": "https://ciec-ccie.parl.gc.ca/en/investigations-enquetes/Pages/ratansiReport.aspx"
            }
          ]
        }
        """

        let snapshot = try EthicsInvestigationsDatabase.decode(data: Data(json.utf8))

        #expect(snapshot.source.title.contains("Conflict of Interest"))
        #expect(snapshot.investigations.count == 2)
        #expect(snapshot.investigations[0].subjectLastName == "Fergus")
        #expect(snapshot.investigations[0].type == "Act")
        #expect(snapshot.investigations[1].subjectLastName == "Ratansi")
    }

    @Test func formatsDate() {
        #expect(EthicsInvestigationsDatabase.formattedDate("2023-02-14") == "Feb 14, 2023")
        #expect(EthicsInvestigationsDatabase.formattedDate("bad-date") == "bad-date")
    }

    @Test func loadsBundledSnapshot() throws {
        let snapshot = try #require(EthicsInvestigationsDatabase.snapshot())

        #expect(snapshot.investigations.count > 20)
        let fergusList = EthicsInvestigationsDatabase.investigations(for: "Fergus")
        #expect(fergusList.count == 1)
        #expect(fergusList.first?.subjectFullName == "Greg Fergus")
        let trudeauList = EthicsInvestigationsDatabase.investigations(for: "Trudeau")
        #expect(trudeauList.count == 3)
    }
}
