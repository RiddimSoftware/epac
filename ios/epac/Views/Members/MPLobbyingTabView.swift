import Charts
import SwiftUI

private enum MPLobbyingTabLayout {
    static let cardSpacing: CGFloat = 10
    static let sectionSpacing: CGFloat = 12
    static let summarySpacing: CGFloat = 12
    static let chipPadding = EpacSpacing.xxs
    static let chipCornerRadius = EpacCornerRadius.xs
    static let chipFontSize: CGFloat = 11
    static let chipSpacing: CGFloat = 6
    static let sourceSpacing: CGFloat = 2
    static let rowSpacing: CGFloat = 3
    static let rowVerticalPadding: CGFloat = EpacSpacing.xs
    static let rowHorizontalPadding: CGFloat = EpacSpacing.s
    static let timelineIconWidth: CGFloat = 28
    static let timelineBadgeCornerRadius: CGFloat = EpacCornerRadius.m
    static let timelineTopSpacing: CGFloat = 8
    static let chartHeight: CGFloat = 190
    static let headerIcon = "chart.pie"
    static let loadMoreHeight: CGFloat = 42
    static let percentFormatter: String = "%.0f%%"
    static let ratioFormatter: String = "%.1f×"
    static let listLeadingInset: CGFloat = 14
}

struct MPLobbyingTabView: View {
    let memberID: Int
    let service: MPLobbyingServiceProviding
    private let preloadedResponse: MPLobbyingExposureResponse?
    private let autoLoadOnAppear: Bool

    @Environment(\.openURL) private var openURL

    @State private var response: MPLobbyingExposureResponse = .empty
    @State private var selectedRange: MPLobbyingDateRange = .defaultRange
    @State private var selectedSubject: String? = nil
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var isRetryDisabled = false
    @State private var errorMessage: String?

    private var hasLoadedData: Bool {
        response.total > 0 || !response.timeline.isEmpty
    }

    private var availableSubjects: [String] {
        response.availableSubjects
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .uniqued()
            .sorted()
    }

    private var showLoadMore: Bool {
        response.page < response.pages
    }

    init(
        memberID: Int,
        service: MPLobbyingServiceProviding = BackendMPLobbyingService(),
        preloadedResponse: MPLobbyingExposureResponse? = nil,
        initialSubject: String? = nil,
        autoLoadOnAppear: Bool = true
    ) {
        self.memberID = memberID
        self.service = service
        self.preloadedResponse = preloadedResponse
        self.autoLoadOnAppear = autoLoadOnAppear && preloadedResponse == nil
        self._response = State(initialValue: preloadedResponse ?? .empty)
        self._selectedSubject = State(initialValue: initialSubject)
        self._selectedRange = State(initialValue: .defaultRange)
    }

    init(
        member: ParliamentMember,
        service: MPLobbyingServiceProviding = BackendMPLobbyingService(),
        preloadedResponse: MPLobbyingExposureResponse? = nil,
        initialSubject: String? = nil,
        autoLoadOnAppear: Bool = true
    ) {
        self.init(
            memberID: member.memberID,
            service: service,
            preloadedResponse: preloadedResponse,
            initialSubject: initialSubject,
            autoLoadOnAppear: autoLoadOnAppear
        )
    }

    var body: some View {
        Group {
            if isLoading && response.timeline.isEmpty && !isRetryDisabled {
                ProgressView(NSLocalizedString("lobbying.loading", comment: ""))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ContentUnavailableView {
                    Label(NSLocalizedString("lobbying.error.title", comment: ""), systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button(NSLocalizedString("lobbying.retry", comment: "")) {
                        guard !isRetryDisabled else { return }
                        isRetryDisabled = true
                        Task {
                            defer { isRetryDisabled = false }
                            try? await Task.sleep(for: .seconds(2))
                            await load(reset: true)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRetryDisabled)
                }
            } else if !hasLoadedData {
                ContentUnavailableView {
                    Label(NSLocalizedString("lobbying.empty.title", comment: ""), systemImage: "person.crop.circle.badge.exclamationmark")
                } description: {
                    Text(NSLocalizedString("lobbying.empty.description", comment: ""))
                }
            } else {
                List {
                    Section {
                        if let trendText = trendSummary {
                            Label(trendText, systemImage: "chart.line.uptrend.xyaxis")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        summaryTiles
                    } header: {
                        Text("Summary")
                    }

                    if !response.topOrganizations.isEmpty {
                        Section {
                            ForEach(Array(response.topOrganizations.prefix(3).enumerated()), id: \.element.id) { item in
                                HStack(spacing: MPLobbyingTabLayout.sectionSpacing) {
                                    Text("\(item.offset + 1).")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 16, alignment: .leading)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.element.organizationName)
                                            .font(.subheadline)
                                            .lineLimit(1)
                                        if !item.element.organizationSector.isEmpty {
                                            Text(item.element.organizationSector)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    Spacer()

                                    Text("\(item.element.count)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } header: {
                            Text("Top 3 organizations")
                        }
                    }

                    Section {
                        LazyHGrid(rows: [GridItem(.fixed(60), spacing: MPLobbyingTabLayout.chipSpacing)], alignment: .top, spacing: MPLobbyingTabLayout.chipSpacing) {
                            metricTile(title: "Received", value: String(response.summary.totalCommunications))
                            metricTile(title: "Organizations", value: String(response.summary.uniqueOrganizations))
                            metricTile(title: "Prev. Parliament", value: String(response.summary.previousParliamentCommunications))
                        }
                    } header: {
                        Text("Scope")
                    }

                    if !response.summary.mostFrequentSubject.isEmpty {
                        Section {
                            HStack {
                                Text("Most frequent subject")
                                Spacer()
                                Text(response.summary.mostFrequentSubject)
                                    .fontWeight(response.summary.mostFrequentSubject.isEmpty ? .regular : .semibold)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.trailing)
                            }
                        } header: {
                            Text("Subject focus")
                        }
                    }

                    if !availableSubjects.isEmpty {
                        Section {
                            Picker("Date", selection: $selectedRange) {
                                ForEach(MPLobbyingDateRange.allCases, id: \.self) { range in
                                    Text(range.displayTitle).tag(range)
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding(.vertical, MPLobbyingTabLayout.chipPadding)

                            Picker("Subject", selection: subjectPickerBinding) {
                                Text("All subjects").tag(String?.none)
                                ForEach(availableSubjects, id: \.self) { subject in
                                    Text(subject).tag(Optional(subject))
                                }
                            }
                            .pickerStyle(.menu)
                        } header: {
                            Text("Filters")
                        } footer: {
                            if availableSubjects.isEmpty {
                                Text("No subject filters are available for this result set.")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if !response.subjectDistribution.isEmpty {
                        Section {
                            Chart {
                                ForEach(response.subjectDistribution.sorted(by: { $0.percentage > $1.percentage }), id: \.subject) { item in
                                    BarMark(
                                        x: .value("Subject", item.subject),
                                        y: .value("Percent", item.percentage)
                                    )
                                    .foregroundStyle(by: .value("Subject", item.subject))
                                }
                            }
                            .frame(height: MPLobbyingTabLayout.chartHeight)

                            ForEach(response.subjectDistribution.sorted(by: { $0.percentage > $1.percentage }), id: \.subject) { item in
                                HStack {
                                    Text(item.subject)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(String(format: MPLobbyingTabLayout.percentFormatter, item.percentage))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } header: {
                            Label("Subject breakdown", systemImage: MPLobbyingTabLayout.headerIcon)
                        }
                    }

                    Section {
                        LabeledContent("Party average") {
                            Text(formatCommCount(response.cohortComparison.partyAverage))
                        }
                        LabeledContent("National average") {
                            Text(formatCommCount(response.cohortComparison.nationalAverage))
                        }
                        if !response.cohortComparison.party.isEmpty {
                            LabeledContent("Party") {
                                Text(response.cohortComparison.party)
                            }
                        }
                        LabeledContent("Relative to party") {
                            Text(formatRatio(response.cohortComparison.partyRatio))
                        }
                        LabeledContent("Relative to national") {
                            Text(formatRatio(response.cohortComparison.nationalRatio))
                        }
                    } header: {
                        Text("Cohort comparison")
                    }

                    if !response.topOrganizations.isEmpty {
                        Section {
                            ForEach(response.topOrganizations) { org in
                                VStack(alignment: .leading, spacing: MPLobbyingTabLayout.rowSpacing) {
                                    HStack(alignment: .top, spacing: MPLobbyingTabLayout.sectionSpacing) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(org.organizationName)
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                            if !org.organizationSector.isEmpty {
                                                Text(org.organizationSector)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                        Text("\(org.count)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    if !org.organizationName.isEmpty {
                                        NavigationLink(destination: LobbyistOrganizationView(organizationName: org.organizationName)) {
                                            Text("View organization profile")
                                                .font(.caption)
                                                .foregroundStyle(.tint)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, MPLobbyingTabLayout.chipPadding)
                                .accessibilityElement(children: .combine)
                            }
                        } header: {
                            Text("Top organizations")
                        }
                        footer: {
                            Text("Top organizations are ranked by number of recorded communications.")
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !response.timeline.isEmpty {
                        Section {
                            ForEach(Array(response.timeline.enumerated()), id: \.element.id) { index, entry in
                                timelineRow(entry)
                                    .onAppear {
                                        if index == response.timeline.count - 1 {
                                            Task { await loadMoreIfPossible() }
                                        }
                                    }
                            }

                            if showLoadMore {
                                Button {
                                    Task { await loadMore() }
                                } label: {
                                    HStack {
                                        Spacer()
                                        if isLoadingMore {
                                            ProgressView()
                                                .scaleEffect(0.8)
                                        } else {
                                            Text("Load more")
                                        }
                                        Spacer()
                                    }
                                    .frame(height: MPLobbyingTabLayout.loadMoreHeight)
                                }
                                .disabled(isLoadingMore)
                                .buttonStyle(.plain)
                                .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                            }
                        } header: {
                            Text("Communications")
                        } footer: {
                            Text("Source: Office of the Commissioner of Lobbying (OCL). Each row links to source records.")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section {
                        DataSourceBadge(source: .lobbyist)
                    } footer: {
                        Text("Data from the Commissioner of Lobbying registry is matched by subject mapping and publication dates for current Parliament.")
                            .foregroundStyle(.secondary)
                    }
                }
                .listStyle(.insetGrouped)
                .adaptiveReadingWidth()
                .accessibilityIdentifier("lobbying-list-scroll")
            }
        }
        .navigationTitle(NSLocalizedString("lobbying.navTitle", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .animation(.default, value: selectedRange)
        .animation(.default, value: selectedSubject)
        .task {
            if autoLoadOnAppear {
                await load(reset: true)
            }
        }
        .onChange(of: selectedRange) { _, _ in
            guard autoLoadOnAppear else { return }
            Task { await load(reset: true) }
        }
        .onChange(of: selectedSubject) { _, _ in
            guard autoLoadOnAppear else { return }
            Task { await load(reset: true) }
        }
    }

    @ViewBuilder
    private var summaryTiles: some View {
        HStack(spacing: MPLobbyingTabLayout.chipSpacing) {
            if response.summary.totalCommunications > 0 {
                chip(title: "Total communications", value: "\(response.summary.totalCommunications)")
            }

            if response.summary.uniqueOrganizations > 0 {
                chip(title: "Organizations", value: String(response.summary.uniqueOrganizations))
            }

            if !response.summary.mostFrequentSubject.isEmpty {
                chip(title: "Most frequent", value: response.summary.mostFrequentSubject)
            }

            chip(title: "Prev. Parliament", value: String(response.summary.previousParliamentCommunications))
        }
        .font(.caption)
    }

    private var subjectPickerBinding: Binding<String?> {
        Binding(
            get: { selectedSubject },
            set: { selectedSubject = $0 }
        )
    }

    private var trendSummary: String? {
        let trend = response.summary.trendVsPreviousParliament
        if response.summary.previousParliamentCommunications <= 0 {
            return NSLocalizedString("lobbying.trend.noComparable", comment: "")
        }
        if trend == 0 {
            return NSLocalizedString("lobbying.trend.noComparable", comment: "")
        }

        let trendText = String(format: MPLobbyingTabLayout.ratioFormatter, trend)

        if trend > 1 {
            return String(format: NSLocalizedString("lobbying.trend.more", comment: ""), trendText)
        }

        if trend == 1 {
            return NSLocalizedString("lobbying.trend.same", comment: "")
        }

        return String(format: NSLocalizedString("lobbying.trend.less", comment: ""), trendText)
    }

    @ViewBuilder
    private func chip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
        .padding(.vertical, MPLobbyingTabLayout.chipPadding)
        .padding(.horizontal, MPLobbyingTabLayout.chipPadding)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: MPLobbyingTabLayout.chipCornerRadius))
    }

    private func metricTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, MPLobbyingTabLayout.chipPadding)
    }

    private func timelineRow(_ entry: MPLobbyingTimelineEntry) -> some View {
        VStack(alignment: .leading, spacing: MPLobbyingTabLayout.rowSpacing) {
            HStack(alignment: .top, spacing: MPLobbyingTabLayout.sectionSpacing) {
                VStack(alignment: .leading, spacing: 2) {
                    if let date = entry.communicationDateValue {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Date not provided")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(entry.organizationName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .fixedSize(horizontal: false, vertical: true)

                    if !entry.organizationSector.isEmpty {
                        Text(entry.organizationSector)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Text(entry.communicationType)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, MPLobbyingTabLayout.chipPadding)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1), in: Capsule())
            }

            if !entry.subjectMatter.isEmpty {
                Text(entry.subjectMatter)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if entry.relatedBillConfidenceUsed, !entry.relatedBillTitle.isEmpty, let billURL = URL(string: entry.relatedBillURL), !entry.relatedBillURL.isEmpty {
                Button {
                    openURL(billURL)
                } label: {
                    Text(NSLocalizedString("lobbying.relatedBill", comment: "") + ": " + entry.relatedBillTitle)
                        .font(.caption)
                        .foregroundStyle(.tint)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
            }

            if let recordURL = URL(string: entry.recordURL), !entry.recordURL.isEmpty {
                Button {
                    openURL(recordURL)
                } label: {
                    Text(NSLocalizedString("lobbying.sourceLabel", comment: ""))
                        .font(.caption)
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, MPLobbyingTabLayout.rowVerticalPadding)
        .padding(.leading, MPLobbyingTabLayout.listLeadingInset)
        .accessibilityElement(children: .combine)
    }

    private func formatCommCount(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return String(format: "%.1f", rounded)
    }

    private func formatRatio(_ value: Double) -> String {
        if value == 0 {
            return "Not available"
        }
        return String(format: MPLobbyingTabLayout.ratioFormatter, value)
    }

    @MainActor
    private func load(reset: Bool) async {
        guard !isLoading, !isLoadingMore else { return }
        if reset {
            await loadInitial()
        } else {
            await appendNextPage()
        }
    }

    @MainActor
    private func loadInitial() async {
        guard autoLoadOnAppear else { return }
        isLoading = true
        errorMessage = nil
        let subject = selectedSubject?.isEmpty == false ? selectedSubject : nil
        do {
            response = try await service.fetchExposure(
                memberID: memberID,
                page: 1,
                range: selectedRange,
                subject: subject
            )
            pruneSubjectFilterIfNeeded()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    @MainActor
    private func appendNextPage() async {
        isLoadingMore = true
        let subject = selectedSubject?.isEmpty == false ? selectedSubject : nil
        do {
            let newResponse = try await service.fetchExposure(
                memberID: memberID,
                page: response.page + 1,
                range: selectedRange,
                subject: subject
            )
            let mergedTimeline = response.timeline + newResponse.timeline
            response = MPLobbyingExposureResponse(
                memberID: newResponse.memberID,
                page: newResponse.page,
                perPage: newResponse.perPage,
                total: newResponse.total,
                pages: newResponse.pages,
                summary: newResponse.summary,
                timeline: mergedTimeline,
                subjectDistribution: newResponse.subjectDistribution,
                topOrganizations: newResponse.topOrganizations,
                cohortComparison: newResponse.cohortComparison,
                availableSubjects: newResponse.availableSubjects
            )
            pruneSubjectFilterIfNeeded()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingMore = false
    }

    private func pruneSubjectFilterIfNeeded() {
        guard let subject = selectedSubject,
              !response.availableSubjects.contains(subject) else { return }
        selectedSubject = nil
    }

    private func loadMoreIfPossible() async {
        guard showLoadMore else { return }
        await load(reset: false)
    }

    private func loadMore() async {
        await load(reset: false)
    }
}

private extension Array where Element == String {
    func uniqued() -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for element in self {
            if seen.insert(element).inserted {
                out.append(element)
            }
        }
        return out
    }
}
