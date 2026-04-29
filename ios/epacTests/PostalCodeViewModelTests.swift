@testable import epac
import Foundation
import Testing

@MainActor
struct PostalCodeViewModelTests {
    @Test func currentMemberResolverIgnoresHistoricalMembersForSameRiding() {
        let paddy = makeMember(
            name: "Paddy Torsney",
            riding: "Burlington",
            party: .liberal,
            fromDateTime: date(year: 1993),
            toDateTime: date(year: 2004)
        )
        let karina = makeMember(
            name: "Karina Gould",
            riding: "Burlington",
            party: .liberal,
            fromDateTime: date(year: 2015),
            toDateTime: nil
        )

        let resolved = PostalCodeViewModel.currentMember(for: "Burlington", in: [paddy, karina])

        #expect(resolved?.name == "Karina Gould")
    }

    @Test func currentMemberResolverReturnsNewestCurrentMatchWhenMultipleCurrentRowsExist() {
        let olderCurrent = makeMember(
            name: "Earlier Current MP",
            riding: "Burlington",
            fromDateTime: date(year: 2019),
            toDateTime: nil
        )
        let newerCurrent = makeMember(
            name: "Latest Current MP",
            riding: "Burlington",
            fromDateTime: date(year: 2025),
            toDateTime: nil
        )

        let resolved = PostalCodeViewModel.currentMember(for: "Burlington", in: [olderCurrent, newerCurrent])

        #expect(resolved?.name == "Latest Current MP")
    }

    @Test func currentMemberResolverReturnsNilWhenOnlyHistoricalMatchExists() {
        let historical = makeMember(
            name: "Historical MP",
            riding: "Burlington",
            fromDateTime: date(year: 1993),
            toDateTime: date(year: 2004)
        )

        let resolved = PostalCodeViewModel.currentMember(for: "Burlington", in: [historical])

        #expect(resolved == nil)
    }

    @Test func currentMemberResolverNormalizesRidingNames() {
        let member = makeMember(
            name: "Current MP",
            riding: "Berthier-Maskinonge",
            fromDateTime: date(year: 2021),
            toDateTime: nil
        )

        let resolved = PostalCodeViewModel.currentMember(for: "Berthier\u{2014}Maskinongé", in: [member])

        #expect(resolved?.name == "Current MP")
    }

    private func makeMember(
        name: String,
        riding: String,
        party: Party = .liberal,
        fromDateTime: Date?,
        toDateTime: Date?
    ) -> ParliamentMember {
        ParliamentMember(
            name: name,
            lastName: String(name.split(separator: " ").last ?? ""),
            firstName: String(name.split(separator: " ").first ?? ""),
            photoURL: URL(string: "https://example.com/photo.jpg")!,
            riding: riding,
            province: .Ontario,
            party: party,
            fromDateTime: fromDateTime,
            toDateTime: toDateTime
        )
    }

    private func date(year: Int) -> Date {
        DateComponents(calendar: Calendar(identifier: .gregorian), year: year, month: 1, day: 1).date!
    }
}
