@testable import epac
import SnapshotTesting
import SwiftUI
import XCTest

final class MemberBiographySnapshotTests: XCTestCase {

    private var isRecording: Bool {
        ProcessInfo.processInfo.environment["UPDATE_SNAPSHOTS"] == "true"
    }

    func testPopulatedBiographyCard() {
        snapshot(
            MemberBiographyCard(
                member: Self.member,
                biography: Self.biography
            )
            .frame(width: 375)
            .padding(),
            name: "populated"
        )
    }

    private func snapshot<V: View>(
        _ view: V,
        name: String,
        file: StaticString = #file,
        testName: String = #function,
        line: UInt = #line
    ) {
        let light = UIHostingController(rootView: view.environment(\.colorScheme, .light))
        let dark = UIHostingController(rootView: view.environment(\.colorScheme, .dark))
        let accessibility = UIHostingController(rootView: view.environment(\.sizeCategory, .accessibilityLarge))

        assertSnapshot(
            of: light,
            as: .image(on: .iPhone13Pro),
            named: "\(name)_light",
            record: isRecording,
            file: file,
            testName: testName,
            line: line
        )
        assertSnapshot(
            of: dark,
            as: .image(on: .iPhone13Pro),
            named: "\(name)_dark",
            record: isRecording,
            file: file,
            testName: testName,
            line: line
        )
        assertSnapshot(
            of: accessibility,
            as: .image(on: .iPhone13Pro),
            named: "\(name)_a11y",
            record: isRecording,
            file: file,
            testName: testName,
            line: line
        )
    }

    private static let member = ParliamentMember(
        name: "Liberal MP",
        lastName: "MP",
        firstName: "Liberal",
        photoURL: URL(string: "https://example.com/photo.jpg")!,
        riding: "Test-Riding",
        province: .Ontario,
        party: .liberal,
        memberID: 1
    )

    private static let biography = MemberBiography(
        yearsServed: [
            ParliamentaryServicePeriod(id: "45-1", label: "45-1", fromDate: "2025-04-28", toDate: nil)
        ],
        previousRoles: [
            ParliamentaryRole(
                id: "health",
                title: "Shadow Minister for Health",
                organization: nil,
                startDate: "2022-09-01",
                endDate: "2024-01-30"
            )
        ],
        education: ["University of Ottawa, MD"],
        professionalBackground: ["Family physician before entering Parliament."],
        sponsoredBills: [
            SponsoredBillReference(
                id: "c-234",
                number: "C-234",
                title: "Living Donor Recognition Medal Act",
                relationship: "sponsored",
                legisInfoURL: URL(string: "https://www.parl.ca/legisinfo/en/bill/45-1/c-234")
            )
        ],
        sourceURL: URL(string: "https://www.ourcommons.ca/Members/en/2269"),
        officialProfileURL: URL(string: "https://www.ourcommons.ca/Members/en/2269")
    )
}
