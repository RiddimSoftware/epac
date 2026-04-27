import Foundation
import Testing
@testable import epac

struct TorontoCouncilServiceTests {
    @Test func parsesOpenDataVoteRecord() {
        let records: [[String: Any]] = [[
            "_id": 42,
            "First Name": "Olivia",
            "Last Name": "Chow",
            "Date/Time": "2026-04-23 16:22 PM",
            "Agenda Item #": "2026.MM40.46",
            "Agenda Item Title": "Affordable Housing Delivery",
            "Motion Type": "Amend Item",
            "Vote": "Yes",
            "Result": "Carried, 22-0",
            "Vote Description": "Additional housing direction"
        ]]

        let votes = TorontoCouncilService.parseVoteRecords(records)

        #expect(votes.count == 1)
        #expect(votes[0].id == "42")
        #expect(votes[0].agendaItemNumber == "2026.MM40.46")
        #expect(votes[0].councillorName == "Olivia Chow")
        #expect(votes[0].voteDetail == "Yes")
        #expect(votes[0].category == .housing)
        #expect(votes[0].date > Date.distantPast)
    }

    @Test func detectsTorontoFederalRidings() {
        #expect(TorontoCouncilService.isTorontoRiding("Toronto Centre"))
        #expect(TorontoCouncilService.isTorontoRiding("Spadina-Fort York"))
        #expect(TorontoCouncilService.isTorontoRiding("Scarborough-Rouge Park"))
        #expect(!TorontoCouncilService.isTorontoRiding("Vancouver East"))
    }

    @Test func matchesCouncillorByTorontoWardName() {
        let councillors = [
            TorontoCouncillor(
                id: "ward-13-moise",
                firstName: "Chris",
                lastName: "Moise",
                wardNumber: 13,
                wardName: "Toronto Centre",
                party: "Independent",
                role: "Councillor",
                email: nil,
                profileURL: URL(string: "https://www.toronto.ca/")!
            ),
            TorontoCouncillor(
                id: "ward-19-bradford",
                firstName: "Brad",
                lastName: "Bradford",
                wardNumber: 19,
                wardName: "Beaches-East York",
                party: "Independent",
                role: "Councillor",
                email: nil,
                profileURL: URL(string: "https://www.toronto.ca/")!
            )
        ]

        let matched = TorontoCouncilService.councillors(for: "Toronto Centre", in: councillors)

        #expect(matched.map(\.lastName) == ["Moise"])
    }
}
