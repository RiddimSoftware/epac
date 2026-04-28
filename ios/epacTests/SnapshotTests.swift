import XCTest
import SnapshotTesting
import SwiftUI
@testable import epac

// Snapshot tests for the app's primary display components.
//
// Reference images live in __Snapshots__/SnapshotTests/ and are committed.
// To regenerate after an intentional UI change:
//   isRecording = true  (flip the constant below)  OR
//   run with UPDATE_SNAPSHOTS=true in the scheme environment variables.
//
// Each view is snapshotted in three configurations: light, dark, and
// Accessibility Large text (accessibilityLarge Dynamic Type category).

final class SnapshotTests: XCTestCase {

    // Flip to true or set UPDATE_SNAPSHOTS=true to regenerate references.
    private var isRecording: Bool {
        ProcessInfo.processInfo.environment["UPDATE_SNAPSHOTS"] == "true"
    }

    // MARK: - Helpers

    private func snapshot<V: View>(
        _ view: V,
        name: String,
        file: StaticString = #file,
        testName: String = #function,
        line: UInt = #line
    ) {
        let light = UIHostingController(rootView: view.environment(\.colorScheme, .light))
        let dark  = UIHostingController(rootView: view.environment(\.colorScheme, .dark))
        let a11y  = UIHostingController(rootView: view.environment(\.sizeCategory, .accessibilityLarge))

        assertSnapshot(of: light, as: .image(on: .iPhone13Pro), named: "\(name)_light",
                       record: isRecording, file: file, testName: testName, line: line)
        assertSnapshot(of: dark,  as: .image(on: .iPhone13Pro), named: "\(name)_dark",
                       record: isRecording, file: file, testName: testName, line: line)
        assertSnapshot(of: a11y,  as: .image(on: .iPhone13Pro), named: "\(name)_a11y",
                       record: isRecording, file: file, testName: testName, line: line)
    }

    private static func member(party: Party) -> ParliamentMember {
        ParliamentMember(
            name: "\(party.fullName) MP",
            lastName: "MP",
            firstName: party.fullName,
            photoURL: URL(string: "https://example.com/photo.jpg")!,
            riding: "Test—Riding",
            province: .Ontario,
            party: party,
            memberID: 1
        )
    }

    // MARK: - MemberRow

    func testMemberRow_liberal() {
        snapshot(
            MemberRow(member: Self.member(party: .liberal))
                .frame(width: 375)
                .padding(),
            name: "MemberRow_liberal"
        )
    }

    func testMemberRow_conservative() {
        snapshot(
            MemberRow(member: Self.member(party: .conservative))
                .frame(width: 375)
                .padding(),
            name: "MemberRow_conservative"
        )
    }

    // MARK: - PartyBadge

    func testPartyBadge_allParties() {
        let badges = HStack(spacing: 8) {
            ForEach(Party.allCases) { party in
                PartyBadge(party: party)
            }
        }
        .padding()

        let lightVC = UIHostingController(rootView: badges.environment(\.colorScheme, .light))
        let darkVC  = UIHostingController(rootView: badges.environment(\.colorScheme, .dark))

        assertSnapshot(of: lightVC, as: .image(on: .iPhone13Pro), named: "PartyBadge_all_light", record: isRecording)
        assertSnapshot(of: darkVC,  as: .image(on: .iPhone13Pro), named: "PartyBadge_all_dark",  record: isRecording)
    }

    // MARK: - BillRow

    private static func makeBill(number: String, title: String, status: BillStatus, stage: String) -> Bill {
        Bill(
            id: number, number: number, title: title,
            sponsorName: "Jane Smith", status: status, currentStage: stage,
            introducedDate: nil, stages: [],
            legisInfoURL: URL(string: "https://www.parl.ca/legisinfo/en/bill/44-1/c-50")!,
            billType: .houseGovernment, parliament: 44, session: 1
        )
    }

    func testBillRow_inProgress() {
        snapshot(
            BillRow(bill: Self.makeBill(number: "C-50", title: "An Act to Amend the Income Tax Act",
                                        status: .inProgress, stage: "Second Reading"))
                .frame(width: 375)
                .padding(),
            name: "BillRow_inProgress"
        )
    }

    func testBillRow_royalAssent() {
        snapshot(
            BillRow(bill: Self.makeBill(number: "C-1",
                                        title: "An Act Respecting the Administration of Oaths of Office",
                                        status: .royalAssent, stage: "Royal Assent"))
                .frame(width: 375)
                .padding(),
            name: "BillRow_royalAssent"
        )
    }

    // MARK: - EmptyStateView

    func testEmptyStateView_noAction() {
        snapshot(
            EmptyStateView(
                icon: "doc.text",
                title: "No Bills Found",
                message: "There are no bills matching your current filters.",
                action: nil
            )
            .frame(width: 375, height: 300),
            name: "EmptyStateView_noAction"
        )
    }

    func testEmptyStateView_withAction() {
        snapshot(
            EmptyStateView(
                icon: "magnifyingglass",
                title: "No Results",
                message: "Try a different search term.",
                action: EmptyStateAction(label: "Clear Search", handler: {})
            )
            .frame(width: 375, height: 300),
            name: "EmptyStateView_withAction"
        )
    }

    // MARK: - DataSourceBadge

    func testDataSourceBadge_hansard() {
        snapshot(
            DataSourceBadge(source: .hansard())
                .padding(),
            name: "DataSourceBadge_hansard"
        )
    }

    func testDataSourceBadge_votes() {
        snapshot(
            DataSourceBadge(source: .votes())
                .padding(),
            name: "DataSourceBadge_votes"
        )
    }

    // MARK: - HomeFeed states (EPAC-434)

    func testHomeFeed_emptyState() {
        snapshot(
            EmptyStateView(
                icon: "person.wave.2",
                title: "Set up your civic feed",
                message: "Add your postal code to track your MP, or follow topics and bills that matter to you.",
                action: EmptyStateAction(label: "Find my MP", handler: {})
            )
            .frame(width: 375, height: 400),
            name: "HomeFeed_emptyState"
        )
    }

    func testHomeFeed_offlineBanner() {
        snapshot(
            Label("Offline — showing cached data from Apr 28, 2026 at 9:30 AM", systemImage: "wifi.slash")
                .font(.epacCaption)
                .foregroundStyle(Color.epacStatus.warning)
                .padding()
                .frame(width: 375),
            name: "HomeFeed_offlineBanner"
        )
    }

    func testHomeFeed_refreshErrorToast() {
        snapshot(
            HomeRefreshErrorToast()
                .frame(width: 375),
            name: "HomeFeed_refreshErrorToast"
        )
    }

    // MARK: - Design system tokens (EPAC-440)

    func testDesignSystem_colorTokens() {
        snapshot(
            DesignSystemColorTokensPreview()
                .frame(width: 375),
            name: "DesignSystem_colorTokens"
        )
    }

    func testDesignSystem_typographyScale() {
        snapshot(
            DesignSystemTypographyPreview()
                .frame(width: 375),
            name: "DesignSystem_typographyScale"
        )
    }
}
