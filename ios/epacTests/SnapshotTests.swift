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
        return try ModelContainer(for: Schema(SchemaV11.models), configurations: config)
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

    private static func makeBill(
        number: String,
        title: String,
        status: BillStatus,
        stage: String,
        royalAssentDate: Date? = nil,
        summary: String? = nil
    ) -> Bill {
        Bill(
            id: number, number: number, title: title,
            sponsorName: "Jane Smith", status: status, currentStage: stage,
            introducedDate: nil,
            royalAssentDate: royalAssentDate,
            summary: summary,
            sponsorProfileURL: URL(string: "https://www.ourcommons.ca/members/en/jane-smith(12345)"),
            stages: [],
            legisInfoURL: URL(string: "https://www.parl.ca/legisinfo/en/bill/44-1/c-50")!,
            type: .government, parliament: 44, session: 1
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

    func testRecentlyBecameLawCard() {
        let bill = Self.makeBill(
            number: "C-12",
            title: "Strengthening Canada's Immigration System and Borders Act",
            status: .royalAssent,
            stage: "Royal Assent",
            royalAssentDate: Self.date("2026-06-10"),
            summary: "An Act respecting certain measures relating to the security of Canada's borders and the integrity of the Canadian immigration system."
        )

        snapshot(
            NavigationStack {
                List {
                    Section("Recently Became Law") {
                        RecentlyBecameLawCard(bills: [bill])
                    }
                }
                .listStyle(.insetGrouped)
            }
            .frame(width: 375, height: 360),
            name: "RecentlyBecameLawCard"
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

    // MARK: - Contracts browser (EPAC-722)

    private static func makeContract(
        id: String = "REF-001",
        vendor: String = "Acme Consulting Inc.",
        department: String = "Public Services and Procurement Canada",
        value: Double = 250_000,
        purpose: String = "Professional advisory services",
        amendmentCount: Int = 0,
        originalValue: Double? = nil,
        endDate: Date? = nil,
        contractType: String = "Services"
    ) -> GovernmentContract {
        GovernmentContract(
            id: id,
            department: department,
            vendor: vendor,
            value: value,
            purpose: purpose,
            contractDate: Calendar.current.date(from: DateComponents(year: 2024, month: 6, day: 15))!,
            endDate: endDate,
            amendmentCount: amendmentCount,
            originalValue: originalValue ?? value,
            fiscalYear: "2024-2025",
            contractType: contractType
        )
    }

    func testContractsBrowser_empty() {
        snapshot(
            EmptyStateView(
                icon: "doc.text.magnifyingglass",
                title: "No contracts found",
                message: "No contracts match your search. Try a vendor or department name.",
                action: nil
            )
            .frame(width: 375, height: 400),
            name: "ContractsBrowser_empty"
        )
    }

    func testContractsBrowser_withResults() {
        let contracts = [
            Self.makeContract(id: "REF-001", vendor: "McKinsey & Company", department: "Public Services and Procurement Canada", value: 4_500_000),
            Self.makeContract(id: "REF-002", vendor: "Deloitte Canada", department: "Treasury Board of Canada Secretariat", value: 875_000),
            Self.makeContract(id: "REF-003", vendor: "KPMG LLP", department: "Health Canada", value: 120_000, amendmentCount: 2)
        ]
        let rows = VStack(spacing: 0) {
            ForEach(contracts) { contract in
                Divider()
                FederalContractRow(contract: contract)
                    .padding(.horizontal)
            }
        }
        .frame(width: 375)
        snapshot(rows, name: "ContractsBrowser_withResults")
    }

    func testContractDetail_withAmendments() {
        let contract = Self.makeContract(
            id: "REF-2024-0042",
            vendor: "McKinsey & Company Canada",
            department: "Public Services and Procurement Canada",
            value: 4_500_000,
            purpose: "Transformation advisory services for federal procurement modernization initiative.",
            amendmentCount: 3,
            originalValue: 2_000_000,
            endDate: Calendar.current.date(from: DateComponents(year: 2025, month: 3, day: 31)),
            contractType: "Services"
        )
        snapshot(
            NavigationStack {
                FederalContractDetailView(contract: contract)
            }
            .frame(width: 375, height: 700),
            name: "ContractDetail_withAmendments"
        )
    }

    // MARK: - MP Lobbying dashboard (EPAC-694)

    @MainActor
    func testMPLobbyingTab_communicationsPresent() {
        snapshot(
            NavigationView {
                MPLobbyingTabView(
                    member: Self.member(party: .liberal),
                    preloadedResponse: Self.sampleLobbyingExposureResponse()
                )
            }
            .frame(width: 375),
            name: "MPLobbyingTab_communicationsPresent"
        )
    }

    @MainActor
    func testMPLobbyingTab_emptyState() {
        snapshot(
            NavigationView {
                MPLobbyingTabView(
                    member: Self.member(party: .green),
                    preloadedResponse: .empty
                )
            }
            .frame(width: 375),
            name: "MPLobbyingTab_emptyState"
        )
    }

    @MainActor
    func testMPLobbyingTab_filteredState() {
        snapshot(
            NavigationView {
                MPLobbyingTabView(
                    member: Self.member(party: .conservative),
                    preloadedResponse: Self.sampleLobbyingExposureResponse(filterMode: true),
                    initialSubject: "Health"
                )
            }
            .frame(width: 375),
            name: "MPLobbyingTab_filteredState"
        )
    }

    private static func sampleLobbyingExposureResponse(filterMode: Bool = false) -> MPLobbyingExposureResponse {
        let timeline: [MPLobbyingTimelineEntry] = [
            MPLobbyingTimelineEntry(
                communicationDate: "2026-04-02",
                organizationName: "Fiscal Policy Group",
                organizationSector: "Finance",
                subjectMatter: "Banking oversight",
                communicationType: "meeting",
                organizationID: "fpg",
                organizationProfileURL: "https://example.com/org/fpg",
                relatedBillTitle: "Financial Institutions Reform Act",
                relatedBillURL: "https://www.parl.ca/legisinfo/en/bill/44-1/c-14",
                relatedBillConfidence: 0.91,
                relatedBillConfidenceUsed: true,
                recordURL: "https://lobbycanada.gc.ca/record/12"
            ),
            MPLobbyingTimelineEntry(
                communicationDate: "2026-03-15",
                organizationName: "North Health Partners",
                organizationSector: "Health",
                subjectMatter: filterMode ? "Health policy" : "Health policy",
                communicationType: "written",
                organizationID: "nhp",
                organizationProfileURL: "https://example.com/org/nhp",
                relatedBillTitle: "",
                relatedBillURL: "",
                relatedBillConfidence: 0,
                relatedBillConfidenceUsed: false,
                recordURL: "https://lobbycanada.gc.ca/record/13"
            )
        ]

        let subjects = filterMode ? ["Health"] : ["Health", "Finance"]
        let topOrganizations = filterMode ? [
            MPLobbyingTopOrganization(
                organizationName: "North Health Partners",
                organizationSector: "Health",
                count: 2,
                organizationID: "nhp",
                organizationProfileURL: "https://example.com/org/nhp"
            )
        ] : [
            MPLobbyingTopOrganization(
                organizationName: "Fiscal Policy Group",
                organizationSector: "Finance",
                count: 5,
                organizationID: "fpg",
                organizationProfileURL: "https://example.com/org/fpg"
            ),
            MPLobbyingTopOrganization(
                organizationName: "North Health Partners",
                organizationSector: "Health",
                count: 2,
                organizationID: "nhp",
                organizationProfileURL: "https://example.com/org/nhp"
            )
        ]

        return MPLobbyingExposureResponse(
            memberID: "278707",
            page: 1,
            perPage: 50,
            total: timeline.count,
            pages: 1,
            summary: MPLobbyingSummary(
                totalCommunications: 7,
                uniqueOrganizations: 2,
                mostFrequentSubject: "Finance",
                previousParliamentCommunications: 2,
                trendVsPreviousParliament: filterMode ? 0 : 3.0
            ),
            timeline: timeline,
            subjectDistribution: [
                MPLobbyingSubjectDistribution(subject: "Finance", count: 1, percentage: 50),
                MPLobbyingSubjectDistribution(subject: "Health", count: 1, percentage: 50)
            ],
            topOrganizations: topOrganizations,
            cohortComparison: MPLobbyingCohortComparison(
                party: "Liberal",
                partyAverage: 4,
                nationalAverage: 3,
                partyRatio: 1.8,
                nationalRatio: 2.3
            ),
            availableSubjects: subjects
        )
    }

    // MARK: - MinisterialExpenseRow (EPAC-817)

    private static func makeMinisterialExpenseRecord(
        ministerName: String = "Mark Carney",
        department: String = "Finance Canada",
        purpose: String = "G7 Finance Ministers Meeting",
        destination: String = "Stresa, Italy",
        totalCost: Double = 18420.50,
        travelCost: Double = 18420.50,
        hospitalityCost: Double = 0.0,
        fiscalYear: String = "2025-2026",
        quarter: Int = 1
    ) -> MinisterialExpenseRecord {
        let cal = Calendar(identifier: .gregorian)
        let startDate = cal.date(from: DateComponents(year: 2025, month: 5, day: 23)) ?? Date()
        let endDate = cal.date(from: DateComponents(year: 2025, month: 5, day: 25))
        return MinisterialExpenseRecord(
            recordID: "test-\(ministerName.lowercased().filter(\.isLetter))-\(destination.lowercased().filter(\.isLetter))",
            ministerName: ministerName,
            department: department,
            eventPurpose: purpose,
            destination: destination,
            startDate: startDate,
            endDate: endDate,
            travelCost: travelCost,
            hospitalityCost: hospitalityCost,
            totalCost: totalCost,
            fiscalYear: fiscalYear,
            quarter: quarter,
            sourceURL: "https://www.canada.ca/en/department-finance/corporate/proactive-disclosure/travel.html"
        )
    }

    @MainActor
    func testMinisterialExpenseRow_withDisclosures() throws {
        let container = try makeSnapshotModelContainer()
        let context = ModelContext(container)
        context.insert(Self.makeMinisterialExpenseRecord())

        snapshot(
            MinisterialExpenseRow(record: Self.makeMinisterialExpenseRecord())
                .frame(width: 375)
                .padding(),
            name: "MinisterialExpenseRow_withDisclosures"
        )
    }

    @MainActor
    func testMinisterialExpenseRow_hospitalityOnly() throws {
        snapshot(
            MinisterialExpenseRow(record: Self.makeMinisterialExpenseRecord(
                purpose: "Budget 2025 stakeholder reception",
                destination: "Ottawa, Ontario",
                totalCost: 4850.0,
                travelCost: 0.0,
                hospitalityCost: 4850.0
            ))
            .frame(width: 375)
            .padding(),
            name: "MinisterialExpenseRow_hospitalityOnly"
        )
    }

    // MARK: - WitnessOrganizationContent (EPAC-614)

    private static func makeAppearance(
        committee: String,
        committeeName: String,
        date: Date?,
        subjects: [String],
        meetingNumber: Int,
        witnesses: [CommitteeWitness]
    ) -> CommitteeAppearance {
        CommitteeAppearance(
            committeeId: committee,
            committeeName: committeeName,
            hearingDate: date,
            subjects: subjects,
            meetingNumber: meetingNumber,
            parliament: 45,
            sessionNumber: 1,
            publicationURL: nil,
            witnesses: witnesses
        )
    }

    private static func makeWitnessOrg(
        name: String,
        witnesses: [CommitteeWitness],
        appearances: [CommitteeAppearance],
        lobbyingCount: Int = 0
    ) -> WitnessOrganization {
        WitnessOrganization(
            id: name.lowercased(),
            displayName: name,
            appearances: appearances,
            individualWitnesses: witnesses,
            lobbyingCount: lobbyingCount
        )
    }

    func testWitnessOrganizationContent_withAppearances() {
        let witnesses = [
            CommitteeWitness(name: "Dr. Jane Smith", title: "President", organization: "Canadian Medical Association"),
            CommitteeWitness(name: "Dr. Amir Patel", title: "Board Member", organization: "Canadian Medical Association")
        ]
        let appearances = [
            Self.makeAppearance(
                committee: "HESA", committeeName: "Standing Committee on Health",
                date: Date(timeIntervalSince1970: 1_748_000_000),
                subjects: ["Health funding", "Physician workforce"],
                meetingNumber: 12, witnesses: [witnesses[0]]
            ),
            Self.makeAppearance(
                committee: "FINA", committeeName: "Standing Committee on Finance",
                date: Date(timeIntervalSince1970: 1_740_000_000),
                subjects: ["Federal health transfers"],
                meetingNumber: 8, witnesses: [witnesses[1]]
            )
        ]
        let org = Self.makeWitnessOrg(name: "Canadian Medical Association", witnesses: witnesses, appearances: appearances)
        snapshot(
            NavigationStack {
                WitnessOrganizationContent(org: org, lobbyingCount: 0)
            }
            .frame(width: 375, height: 700),
            name: "WitnessOrganizationContent_withAppearances"
        )
    }

    func testWitnessOrganizationContent_noAppearances() {
        snapshot(
            ContentUnavailableView(
                "No appearances found",
                systemImage: "person.fill.questionmark",
                description: Text("No committee evidence found for this organization.")
            )
            .frame(width: 375, height: 300),
            name: "WitnessOrganizationContent_noAppearances"
        )
    }

    func testWitnessOrganizationContent_withLobbyingBadge() {
        let witnesses = [
            CommitteeWitness(name: "Alex Dupont", title: "VP Government Relations", organization: "Pharma Corp Canada")
        ]
        let appearances = [
            Self.makeAppearance(
                committee: "HESA", committeeName: "Standing Committee on Health",
                date: Date(timeIntervalSince1970: 1_748_000_000),
                subjects: ["Drug pricing", "Patented medicine regulations"],
                meetingNumber: 5, witnesses: witnesses
            )
        ]
        let org = Self.makeWitnessOrg(name: "Pharma Corp Canada", witnesses: witnesses, appearances: appearances, lobbyingCount: 7)
        snapshot(
            NavigationStack {
                WitnessOrganizationContent(org: org, lobbyingCount: 7)
            }
            .frame(width: 375, height: 700),
            name: "WitnessOrganizationContent_withLobbyingBadge"
        )
    }

    // MARK: - Petitions Government Response

    private struct SnapshotStubPetitionQueryPort: PetitionGovernmentResponseQueryPort {
        let response: PetitionGovernmentResponse?
        func fetchGovernmentResponse(for petitionID: String) async throws -> PetitionGovernmentResponse? {
            response
        }
    }

    func testPetitionDetailView_withResponse() {
        let response = PetitionGovernmentResponse(
            text: "This is the official government response to the petition. The government takes these matters seriously and is committed to implementing appropriate policies.",
            tabledOn: Date(timeIntervalSince1970: 1_773_600_000),
            respondingMinister: "Minister of Justice and Attorney General of Canada"
        )
        let petition = EPetition(
            id: "e-4500",
            subject: "Federal Funding for Civic Infrastructure",
            keywords: ["Infrastructure", "Finance", "Cities"],
            sponsorName: "Pierre Poilievre",
            signatureCount: 1250,
            deadline: nil,
            status: .responseReceived,
            petitionURL: URL(string: "https://petitions.ourcommons.ca/en/Petition/Details?Petition=e-4500")!,
            governmentResponse: response
        )
        let port = SnapshotStubPetitionQueryPort(response: response)
        snapshot(
            NavigationStack {
                PetitionDetailView(petition: petition, queryPort: port)
            }
            .frame(width: 375, height: 750),
            name: "PetitionDetailView_withResponse"
        )
    }

    func testPetitionDetailView_awaitingResponse() {
        let petition = EPetition(
            id: "e-4501",
            subject: "Environmental Protections in Northern Canada",
            keywords: ["Environment", "North", "Climate Change"],
            sponsorName: "Elizabeth May",
            signatureCount: 520,
            deadline: Date(timeIntervalSince1970: 1_773_600_000),
            status: .closed,
            petitionURL: URL(string: "https://petitions.ourcommons.ca/en/Petition/Details?Petition=e-4501")!
        )
        let port = SnapshotStubPetitionQueryPort(response: nil)
        snapshot(
            NavigationStack {
                PetitionDetailView(petition: petition, queryPort: port)
            }
            .frame(width: 375, height: 600),
            name: "PetitionDetailView_awaitingResponse"
        )
    }

    func testPetitionDetailView_notQualified() {
        let petition = EPetition(
            id: "e-4502",
            subject: "Promotion of Amateur Sports Programs",
            keywords: ["Sports", "Health", "Youth"],
            sponsorName: "Jagmeet Singh",
            signatureCount: 230,
            deadline: Date(timeIntervalSince1970: 1_773_600_000),
            status: .closed,
            petitionURL: URL(string: "https://petitions.ourcommons.ca/en/Petition/Details?Petition=e-4502")!
        )
        let port = SnapshotStubPetitionQueryPort(response: nil)
        snapshot(
            NavigationStack {
                PetitionDetailView(petition: petition, queryPort: port)
            }
            .frame(width: 375, height: 600),
            name: "PetitionDetailView_notQualified"
        )
    }
}
