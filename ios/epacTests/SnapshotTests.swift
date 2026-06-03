@testable import epac
import SnapshotTesting
import SwiftData
import SwiftUI
import XCTest

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
        assertSnapshot(of: dark, as: .image(on: .iPhone13Pro), named: "\(name)_dark",
                       record: isRecording, file: file, testName: testName, line: line)
        assertSnapshot(of: a11y, as: .image(on: .iPhone13Pro), named: "\(name)_a11y",
                       record: isRecording, file: file, testName: testName, line: line)
    }

    private func snapshotLightDarkXXL<V: View>(
        _ view: V,
        name: String,
        file: StaticString = #file,
        testName: String = #function,
        line: UInt = #line
    ) {
        let light = UIHostingController(rootView: view.environment(\.colorScheme, .light))
        let dark  = UIHostingController(rootView: view.environment(\.colorScheme, .dark))
        let xxl   = UIHostingController(rootView: view.environment(\.sizeCategory, .extraExtraLarge))

        assertSnapshot(of: light, as: .image(on: .iPhone13Pro), named: "\(name)_light",
                       record: isRecording, file: file, testName: testName, line: line)
        assertSnapshot(of: dark, as: .image(on: .iPhone13Pro), named: "\(name)_dark",
                       record: isRecording, file: file, testName: testName, line: line)
        assertSnapshot(of: xxl, as: .image(on: .iPhone13Pro), named: "\(name)_xxl",
                       record: isRecording, file: file, testName: testName, line: line)
    }

    private func makeSnapshotModelContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Schema(SchemaV10.models), configurations: config)
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
        assertSnapshot(of: darkVC, as: .image(on: .iPhone13Pro), named: "PartyBadge_all_dark", record: isRecording)
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

    // MARK: - Bill lobbying context (EPAC-2159)

    func testBillLobbyingContextPanel_populated() {
        snapshot(
            List {
                BillLobbyingContextPanel(context: Self.billLobbyingContext)
            }
            .listStyle(.insetGrouped)
            .frame(width: 375, height: 420),
            name: "BillLobbyingContextPanel_populated"
        )
    }

    func testBillLobbyingContextPanel_hiddenWhenZero() {
        snapshot(
            List {
                Text("Before")
                BillLobbyingContextPanel(context: .empty)
                Text("After")
            }
            .listStyle(.insetGrouped)
            .frame(width: 375, height: 220),
            name: "BillLobbyingContextPanel_hiddenWhenZero"
        )
    }

    func testBillLobbyingContextPanel_topThreeOrganizations() {
        snapshot(
            List {
                BillLobbyingContextPanel(context: Self.billLobbyingContextWithFiveOrganizations)
            }
            .listStyle(.insetGrouped)
            .frame(width: 375, height: 420),
            name: "BillLobbyingContextPanel_topThreeOrganizations"
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

    // MARK: - Settings IA (EPAC-476)

    @MainActor
    func testSettings_root() throws {
        let postalCode = PostalCodeViewModel()
        postalCode.postalCode = "K1A 0A6"
        postalCode.result = RidingLookupResult(
            memberName: "Sample MP",
            ridingName: "Sample Riding",
            partyName: "Sample Party"
        )
        postalCode.confirm()
        defer { PostalCodeViewModel.clear() }

        snapshotLightDarkXXL(
            SettingsView()
                .modelContainer(try makeSnapshotModelContainer()),
            name: "Settings_root"
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

    // MARK: - Minister lobbying (EPAC-2157)

    @MainActor
    func testMinisterLobbying_twoPortfolios() {
        snapshot(
            MinisterLobbyingTabView(
                memberID: 317577,
                initialPeriods: Self.ministerLobbyingPeriods,
                initialLoadCompleted: true,
                autoload: false
            )
            .frame(width: 375)
            .padding(),
            name: "MinisterLobbying_twoPortfolios"
        )
    }

    @MainActor
    func testMinisterLobbying_empty() {
        snapshot(
            MinisterLobbyingTabView(
                memberID: 42,
                initialPeriods: [],
                initialLoadCompleted: true,
                autoload: false
            )
            .frame(width: 375, height: 360)
            .padding(),
            name: "MinisterLobbying_empty"
        )
    }

    @MainActor
    func testCabinetLobbyingOverview() {
        snapshot(
            CabinetLobbyingOverviewView(
                initialOverview: Self.cabinetLobbyingOverview,
                initialLoadCompleted: true,
                autoload: false
            )
            .frame(width: 375, height: 780),
            name: "CabinetLobbyingOverview"
        )
    }

    // MARK: - MP lobbying (EPAC-2155)

    @MainActor
    func testMPLobbying_present() {
        snapshot(
            ScrollView {
                LobbyingView(
                    memberID: 278707,
                    initialExposure: Self.mpLobbyingExposure,
                    initialLoadCompleted: true,
                    autoload: false
                )
                .padding()
            }
            .frame(width: 375, height: 980),
            name: "MPLobbying_present"
        )
    }

    @MainActor
    func testMPLobbying_empty() {
        snapshot(
            LobbyingView(
                memberID: 42,
                initialExposure: Self.mpLobbyingEmptyExposure,
                initialLoadCompleted: true,
                autoload: false
            )
            .frame(width: 375, height: 420)
            .padding(),
            name: "MPLobbying_empty"
        )
    }

    @MainActor
    func testMPLobbying_filtered() {
        snapshot(
            ScrollView {
                LobbyingView(
                    memberID: 278707,
                    initialExposure: Self.mpLobbyingExposure,
                    initialSubjectSlug: MPLobbyingSubjectDistribution.slug(for: "Housing"),
                    initialLoadCompleted: true,
                    autoload: false
                )
                .padding()
            }
            .frame(width: 375, height: 860),
            name: "MPLobbying_filtered"
        )
    }

    // MARK: - Lobbyist organization profile (EPAC-996)

    @MainActor
    func testLobbyistOrganization_activeWithCommunications() {
        snapshot(
            NavigationStack {
                LobbyistOrganizationView(profile: Self.lobbyistOrganizationActive)
            }
            .frame(width: 375, height: 900),
            name: "LobbyistOrganization_active"
        )
    }

    @MainActor
    func testLobbyistOrganization_expired() {
        snapshot(
            NavigationStack {
                LobbyistOrganizationView(profile: Self.lobbyistOrganizationExpired)
            }
            .frame(width: 375, height: 680),
            name: "LobbyistOrganization_expired"
        )
    }

    @MainActor
    func testLobbyistOrganization_noCommunications() {
        snapshot(
            NavigationStack {
                LobbyistOrganizationView(profile: Self.lobbyistOrganizationNoCommunications)
            }
            .frame(width: 375, height: 680),
            name: "LobbyistOrganization_noCommunications"
        )
    }

    private static var lobbyistOrganizationActive: LobbyistOrganization {
        LobbyistOrganization(
            id: "ocl:42",
            oclOrganizationID: "42",
            name: "Canadian Housing Alliance",
            type: .association,
            sector: "Housing",
            registeredLobbyists: [
                RegisteredLobbyist(name: "Jane Lobbyist", kind: .consultant),
                RegisteredLobbyist(name: "Sam Policy", kind: .inHouse)
            ],
            activeSubjectMatters: ["Housing", "Infrastructure"],
            communicationVolume: LobbyistOrganizationCommunicationVolume(
                currentParliament: 12,
                priorParliament: 5
            ),
            topDPOHsContacted: [
                LobbyistOrganizationDPOHContact(
                    memberID: "278707",
                    name: "Example Minister",
                    institution: "House of Commons",
                    count: 4
                )
            ],
            registrationStatus: .active,
            registrations: [
                LobbyistRegistration(
                    id: "990018",
                    status: .active,
                    kind: .consultant,
                    subjectMatters: ["Housing", "Infrastructure"],
                    targetedInstitutions: ["House of Commons", "Infrastructure Canada"],
                    sourceURL: CabinetLobbyingSource.url
                )
            ],
            recentCommunications: [
                LobbyistOrganizationCommunication(
                    id: "558142",
                    date: date("2026-05-20"),
                    dpohMemberID: "278707",
                    dpohName: "Example Minister",
                    institution: "House of Commons",
                    subjectMatters: ["Housing"],
                    sourceURL: CabinetLobbyingSource.url
                ),
                LobbyistOrganizationCommunication(
                    id: "558143",
                    date: date("2026-05-18"),
                    dpohMemberID: nil,
                    dpohName: "Assistant Deputy Minister",
                    institution: "Infrastructure Canada",
                    subjectMatters: ["Infrastructure"],
                    sourceURL: CabinetLobbyingSource.url
                )
            ],
            subjectMatters: [
                LobbyistOrganizationSubjectMatter(
                    subjectMatter: "Housing",
                    communicationCount: 8,
                    topicSlug: "housing"
                ),
                LobbyistOrganizationSubjectMatter(
                    subjectMatter: "Infrastructure",
                    communicationCount: 4,
                    topicSlug: "transport"
                )
            ],
            citation: CabinetLobbyingSource.citation,
            sourceURL: CabinetLobbyingSource.url
        )
    }

    private static var lobbyistOrganizationExpired: LobbyistOrganization {
        LobbyistOrganization(
            id: "ocl:expired",
            oclOrganizationID: "77",
            name: "Former Energy Council",
            type: .corporation,
            sector: "Energy",
            registeredLobbyists: [
                RegisteredLobbyist(name: "Alex Morgan", kind: .inHouse)
            ],
            activeSubjectMatters: [],
            communicationVolume: LobbyistOrganizationCommunicationVolume(
                currentParliament: 0,
                priorParliament: 9
            ),
            topDPOHsContacted: [],
            registrationStatus: .expired,
            registrations: [
                LobbyistRegistration(
                    id: "881100",
                    status: .expired,
                    kind: .inHouse,
                    subjectMatters: ["Energy"],
                    targetedInstitutions: ["Natural Resources Canada"],
                    sourceURL: CabinetLobbyingSource.url
                )
            ],
            recentCommunications: [
                LobbyistOrganizationCommunication(
                    id: "449900",
                    date: date("2024-11-05"),
                    dpohMemberID: nil,
                    dpohName: "Policy Director",
                    institution: "Natural Resources Canada",
                    subjectMatters: ["Energy"],
                    sourceURL: CabinetLobbyingSource.url
                )
            ],
            subjectMatters: [
                LobbyistOrganizationSubjectMatter(
                    subjectMatter: "Energy",
                    communicationCount: 9,
                    topicSlug: "energy"
                )
            ],
            citation: CabinetLobbyingSource.citation,
            sourceURL: CabinetLobbyingSource.url
        )
    }

    private static var lobbyistOrganizationNoCommunications: LobbyistOrganization {
        LobbyistOrganization(
            id: "ocl:quiet",
            oclOrganizationID: "88",
            name: "Quiet Public Policy Institute",
            type: .nonProfit,
            sector: "Research",
            registeredLobbyists: [
                RegisteredLobbyist(name: "Casey Nguyen", kind: .consultant)
            ],
            activeSubjectMatters: ["Research and development"],
            communicationVolume: LobbyistOrganizationCommunicationVolume(
                currentParliament: 0,
                priorParliament: 0
            ),
            topDPOHsContacted: [],
            registrationStatus: .active,
            registrations: [
                LobbyistRegistration(
                    id: "991122",
                    status: .active,
                    kind: .consultant,
                    subjectMatters: ["Research and development"],
                    targetedInstitutions: [],
                    sourceURL: CabinetLobbyingSource.url
                )
            ],
            recentCommunications: [],
            subjectMatters: [],
            citation: CabinetLobbyingSource.citation,
            sourceURL: CabinetLobbyingSource.url
        )
    }

    private static var ministerLobbyingPeriods: [MinisterPortfolioLobbyingPeriod] {
        [
            MinisterPortfolioLobbyingPeriod(
                portfolioName: "Minister of Environment",
                startDate: date("2023-11-01"),
                endDate: date("2024-09-30"),
                communications: [
                    MinisterLobbyingCommunication(
                        id: "env-1",
                        organizationName: "Canadian Clean Energy Association",
                        lobbyistName: "Alex Morgan",
                        communicationDate: date("2024-04-16"),
                        subjectMatter: "Climate policy, clean electricity regulations",
                        registrantType: "In-house (organization)",
                        registryURL: CabinetLobbyingSource.url,
                        mandateMatch: true,
                        communicationType: "Meeting"
                    ),
                    MinisterLobbyingCommunication(
                        id: "env-2",
                        organizationName: "North Coast Infrastructure Council",
                        lobbyistName: "Priya Shah",
                        communicationDate: date("2024-02-20"),
                        subjectMatter: "Ports, environmental assessment",
                        registrantType: "Consultant",
                        registryURL: CabinetLobbyingSource.url,
                        mandateMatch: false,
                        communicationType: "Written"
                    )
                ]
            ),
            MinisterPortfolioLobbyingPeriod(
                portfolioName: "Minister of Natural Resources",
                startDate: date("2024-10-01"),
                endDate: nil,
                communications: [
                    MinisterLobbyingCommunication(
                        id: "nr-1",
                        organizationName: "Critical Minerals Alliance",
                        lobbyistName: "Jordan Lee",
                        communicationDate: date("2025-01-12"),
                        subjectMatter: "Critical minerals supply chains",
                        registrantType: "In-house (corporation)",
                        registryURL: CabinetLobbyingSource.url,
                        mandateMatch: true,
                        communicationType: "Meeting"
                    )
                ]
            )
        ]
    }

    private static var cabinetLobbyingOverview: CabinetLobbyingOverview {
        CabinetLobbyingOverview(
            parliament: 45,
            ministers: [
                CabinetLobbyingMinisterSummary(
                    memberID: 317577,
                    ministerName: "Mark Carney",
                    portfolioName: "Prime Minister of Canada",
                    totalCommunications: 42,
                    mandateMatchCount: 9
                ),
                CabinetLobbyingMinisterSummary(
                    memberID: 314774,
                    ministerName: "Anita Anand",
                    portfolioName: "Minister of Foreign Affairs",
                    totalCommunications: 31,
                    mandateMatchCount: 4
                ),
                CabinetLobbyingMinisterSummary(
                    memberID: 322130,
                    ministerName: "Steven Guilbeault",
                    portfolioName: "Minister of Environment",
                    totalCommunications: 27,
                    mandateMatchCount: 6
                )
            ],
            portfolioFilters: [
                "Minister of Environment",
                "Minister of Foreign Affairs",
                "Prime Minister of Canada"
            ],
            mostActiveOrganizations: [
                CabinetLobbyingOrganizationSummary(
                    portfolioName: "Minister of Environment",
                    organizationName: "Canadian Clean Energy Association",
                    communicationCount: 12
                ),
                CabinetLobbyingOrganizationSummary(
                    portfolioName: "Minister of Environment",
                    organizationName: "Critical Minerals Alliance",
                    communicationCount: 8
                ),
                CabinetLobbyingOrganizationSummary(
                    portfolioName: "Minister of Foreign Affairs",
                    organizationName: "Global Trade Council",
                    communicationCount: 10
                )
            ]
        )
    }

    private static var mpLobbyingExposure: MPLobbyingExposure {
        MPLobbyingExposure(
            memberID: "278707",
            parliament: 45,
            window: .threeMonths,
            page: 1,
            perPage: MPLobbyingExposureDefaults.pageSize,
            total: 75,
            pages: 2,
            summary: MPLobbyingSummary(
                memberID: "278707",
                parliament: 45,
                quarterStart: date("2026-04-01"),
                window: .threeMonths,
                totalCommunicationCount: 12,
                uniqueOrganizationsCount: 5,
                mostFrequentSubjectMatter: "Housing",
                topOrganizations: [
                    MPLobbyingTopOrganization(
                        name: "Example Housing Association",
                        sector: "Housing",
                        communicationCount: 6
                    ),
                    MPLobbyingTopOrganization(
                        name: "National Builders Council",
                        sector: "Infrastructure",
                        communicationCount: 4
                    ),
                    MPLobbyingTopOrganization(
                        name: "Tenant Rights Network",
                        sector: "Housing",
                        communicationCount: 2
                    ),
                    MPLobbyingTopOrganization(
                        name: "Urban Infrastructure Forum",
                        sector: "Transport",
                        communicationCount: 1
                    ),
                    MPLobbyingTopOrganization(
                        name: "Clean Grid Coalition",
                        sector: "Energy",
                        communicationCount: 1
                    )
                ],
                trendVsPreviousParliament: MPLobbyingTrend(
                    currentParliament: 12,
                    previousParliament: 4,
                    delta: 8
                ),
                partyAverageCommunications: 4.0,
                nationalAverageCommunications: 3.75,
                citation: CabinetLobbyingSource.citation,
                updatedAt: date("2026-06-03")
            ),
            subjectBreakdown: [
                MPLobbyingSubjectDistribution(subjectMatter: "Housing", communicationCount: 8),
                MPLobbyingSubjectDistribution(subjectMatter: "Infrastructure", communicationCount: 4),
                MPLobbyingSubjectDistribution(subjectMatter: "Energy", communicationCount: 2)
            ],
            timeline: [
                MPLobbyingTimelineEntry(
                    communicationID: "558142",
                    date: date("2026-05-20"),
                    organizationName: "Example Housing Association",
                    organizationSector: "Housing",
                    subjectMatter: "Housing",
                    communicationType: "meeting",
                    billCrossReference: MPLobbyingBillCrossReference(
                        billNumber: "C-1",
                        billTitle: "Example Bill",
                        url: URL(string: "https://www.parl.ca/legisinfo/en/bill/45-1/c-1")!,
                        mappingConfidence: 0.93
                    ),
                    citation: CabinetLobbyingSource.citation,
                    sourceURL: CabinetLobbyingSource.url
                ),
                MPLobbyingTimelineEntry(
                    communicationID: "558143",
                    date: date("2026-05-18"),
                    organizationName: "National Builders Council",
                    organizationSector: "Infrastructure",
                    subjectMatter: "Infrastructure",
                    communicationType: "written",
                    billCrossReference: nil,
                    citation: CabinetLobbyingSource.citation,
                    sourceURL: CabinetLobbyingSource.url
                )
            ],
            citation: CabinetLobbyingSource.citation,
            sourceURL: CabinetLobbyingSource.url
        )
    }

    private static var mpLobbyingEmptyExposure: MPLobbyingExposure {
        MPLobbyingExposure(
            memberID: "42",
            parliament: 45,
            window: .allTime,
            page: 1,
            perPage: MPLobbyingExposureDefaults.pageSize,
            total: 0,
            pages: 0,
            summary: MPLobbyingSummary(
                memberID: "42",
                parliament: 45,
                quarterStart: date("2026-04-01"),
                window: .allTime,
                totalCommunicationCount: 0,
                uniqueOrganizationsCount: 0,
                mostFrequentSubjectMatter: nil,
                topOrganizations: [],
                trendVsPreviousParliament: MPLobbyingTrend(
                    currentParliament: 0,
                    previousParliament: 0,
                    delta: 0
                ),
                partyAverageCommunications: 0,
                nationalAverageCommunications: 0,
                citation: CabinetLobbyingSource.citation,
                updatedAt: date("2026-06-03")
            ),
            subjectBreakdown: [],
            timeline: [],
            citation: CabinetLobbyingSource.citation,
            sourceURL: CabinetLobbyingSource.url
        )
    }

    private static var billLobbyingContext: BillLobbyingContext {
        BillLobbyingContext(
            billID: "C-2",
            windowMonths: 12,
            windowStartDate: date("2025-05-15"),
            windowEndDate: date("2026-05-15"),
            subjectTags: ["Housing"],
            totalCommunications: 8,
            organizations: [
                BillLobbyingOrganization(name: "Example Housing Association", communicationCount: 4),
                BillLobbyingOrganization(name: "National Builders Council", communicationCount: 2),
                BillLobbyingOrganization(name: "Tenant Rights Network", communicationCount: 2)
            ],
            topOrganizations: [
                BillLobbyingOrganization(name: "Example Housing Association", communicationCount: 4),
                BillLobbyingOrganization(name: "National Builders Council", communicationCount: 2),
                BillLobbyingOrganization(name: "Tenant Rights Network", communicationCount: 2)
            ],
            sourceURL: CabinetLobbyingSource.url
        )
    }

    private static var billLobbyingContextWithFiveOrganizations: BillLobbyingContext {
        BillLobbyingContext(
            billID: "C-3",
            windowMonths: 12,
            windowStartDate: date("2025-05-15"),
            windowEndDate: date("2026-05-15"),
            subjectTags: ["Environment"],
            totalCommunications: 18,
            organizations: [
                BillLobbyingOrganization(name: "Canadian Clean Energy Association", communicationCount: 6),
                BillLobbyingOrganization(name: "Critical Minerals Alliance", communicationCount: 5),
                BillLobbyingOrganization(name: "North Coast Infrastructure Council", communicationCount: 4),
                BillLobbyingOrganization(name: "Prairie Grid Operators", communicationCount: 2),
                BillLobbyingOrganization(name: "Northern Transit Coalition", communicationCount: 1)
            ],
            topOrganizations: [
                BillLobbyingOrganization(name: "Canadian Clean Energy Association", communicationCount: 6),
                BillLobbyingOrganization(name: "Critical Minerals Alliance", communicationCount: 5),
                BillLobbyingOrganization(name: "North Coast Infrastructure Council", communicationCount: 4),
                BillLobbyingOrganization(name: "Prairie Grid Operators", communicationCount: 2),
                BillLobbyingOrganization(name: "Northern Transit Coalition", communicationCount: 1)
            ],
            sourceURL: CabinetLobbyingSource.url
        )
    }

    private static func date(_ rawValue: String) -> Date {
        dateFormatter.date(from: rawValue) ?? Date(timeIntervalSince1970: 0)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    // MARK: - GrantRow

    private static func makeGrant() -> GrantContribution {
        GrantContribution(
            id: "GC-2025-001",
            recipientName: "University of Ottawa",
            amount: 2_500_000,
            department: "Natural Sciences and Engineering Research Council",
            purpose: "Advanced Research in Renewable Energy Systems",
            recipientLocation: "Ottawa, Ontario",
            recipientProvince: "Ontario",
            recipientType: "Post-secondary institution",
            fiscalYear: "2024-2025",
            agreementDate: Date(timeIntervalSince1970: 1_704_067_200)
        )
    }

    func testGrantRow_populated() {
        snapshot(
            GrantRow(grant: Self.makeGrant())
                .frame(width: 375)
                .padding(),
            name: "GrantRow_populated"
        )
    }

    func testGrantsView_empty() {
        snapshot(
            EmptyStateView(
                icon: "doc.text.magnifyingglass",
                title: "No Grants Found",
                message: "No grants or contributions match your current filters.",
                action: nil
            )
            .frame(width: 375, height: 300),
            name: "GrantsView_empty"
        )
    }

    func testGrantsView_loadError() {
        snapshot(
            EmptyStateView(
                icon: "exclamationmark.triangle",
                title: "Could Not Load Grants",
                message: "Federal grants data could not be loaded. Check your connection and try again.",
                action: EmptyStateAction(label: "Retry", handler: {})
            )
            .frame(width: 375, height: 300),
            name: "GrantsView_loadError"
        )
    }
}
