@testable import epac
import Foundation
import SwiftUI
import Testing

@MainActor
struct BillsSelectionTests {

    @Test func selectingBillWritesBinding() {
        let expected = BillsSelectionTestData.bill(number: "C-50")
        let box = SelectedBillBox()
        let binding = Binding<Bill?>(
            get: { box.bill },
            set: { box.bill = $0 }
        )

        BillsSelection.select(expected, selection: binding)

        #expect(box.bill?.number == expected.number)
    }

    @Test func selectedStateUsesBillIdentity() {
        let selected = BillsSelectionTestData.bill(number: "C-50")
        let selectedWithUpdatedTitle = BillsSelectionTestData.bill(
            number: "C-50",
            title: "Updated title from LEGISinfo"
        )
        let other = BillsSelectionTestData.bill(number: "S-12")

        #expect(BillsSelection.isSelected(selectedWithUpdatedTitle, selectedBill: selected))
        #expect(!BillsSelection.isSelected(other, selectedBill: selected))
        #expect(!BillsSelection.isSelected(selected, selectedBill: nil))
    }

    @Test func matchingSelectionReturnsRefreshedBill() throws {
        let selected = BillsSelectionTestData.bill(number: "C-50")
        let refreshed = BillsSelectionTestData.bill(
            number: "C-50",
            title: "Refreshed bill title"
        )
        let bills = [
            BillsSelectionTestData.bill(number: "S-12"),
            refreshed
        ]

        let match = try #require(BillsSelection.matching(selected, in: bills))

        #expect(match.title == refreshed.title)
    }

    @Test func routerRetainsBillSelectionAcrossTabChanges() {
        let selected = BillsSelectionTestData.bill(number: "C-50")
        let router = NavigationRouter()

        router.selectedBill = selected
        router.selectedTab = .home
        router.selectedTab = .accountability

        #expect(router.selectedBill?.number == selected.number)
    }

    @Test func billNumberFilterMatchesSponsoredBillsCaseInsensitively() {
        let sponsored = BillsSelectionTestData.bill(number: "C-234")
        let other = BillsSelectionTestData.bill(number: "C-50")
        let filter: Set<String> = ["c-234".uppercased()]

        #expect(BillsSelection.matchesBillNumberFilter(sponsored, billNumbersFilter: filter))
        #expect(!BillsSelection.matchesBillNumberFilter(other, billNumbersFilter: filter))
        #expect(BillsSelection.matchesBillNumberFilter(other, billNumbersFilter: []))
    }
}

private enum BillsSelectionTestData {
    static let parliament = 45
    static let session = 1

    static func bill(
        number: String,
        title: String = "An Act to test bill selection"
    ) -> Bill {
        Bill(
            id: number,
            number: number,
            title: title,
            sponsorName: "Jane Smith",
            status: .inProgress,
            currentStage: "Second Reading",
            introducedDate: nil,
            stages: [],
            legisInfoURL: URL(string: "https://www.parl.ca/legisinfo/en/bill/45-1/c-50")!,
            type: .government,
            parliament: parliament,
            session: session
        )
    }
}

@MainActor
private final class SelectedBillBox {
    var bill: Bill?
}
