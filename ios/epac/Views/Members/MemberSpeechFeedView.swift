import SwiftUI
import SwiftData

// MARK: - Response models (Codable mirrors of the member-speeches Lambda response)

struct MemberSpeechEntry: Codable, Identifiable {
    let id: String           // intervention_id
    let sittingDate: String?
    let parliamentNum: Int?
    let sessionNum: Int?
    let subjectTitle: String?
    let preview: String
    let wordCount: Int?
    let filename: String
}

struct MemberSpeechStats: Codable {
    let totalSpeeches: Int
    let avgWordCount: Int
    let topTopic: String
}

private struct SpeechFeedPage: Codable {
    let memberId: String
    let page: Int
    let perPage: Int
    let total: Int
    let pages: Int
    let stats: MemberSpeechStats
    let speeches: [MemberSpeechEntry]
}

// MARK: - ViewModel

@Observable
@MainActor
final class MemberSpeechFeedViewModel {

    let memberId: Int
    private(set) var speeches: [MemberSpeechEntry] = []
    private(set) var stats: MemberSpeechStats?
    private(set) var isLoading = false
    private(set) var hasMore = true
    private(set) var errorMessage: String?
    private(set) var selectedTopic: String? = nil

    // Unique topics from loaded speeches, ordered by frequency.
    var topicCounts: [(topic: String, count: Int)] {
        Self.buildTopicCounts(from: speeches)
    }

    /// Pure helper — extracted for testability.
    static func buildTopicCounts(from speeches: [MemberSpeechEntry]) -> [(topic: String, count: Int)] {
        var counts: [String: Int] = [:]
        for s in speeches {
            if let t = s.subjectTitle, !t.isEmpty {
                counts[t, default: 0] += 1
            }
        }
        return counts.sorted { $0.value > $1.value }.map { (topic: $0.key, count: $0.value) }
    }

    private var currentPage = 0
    private let perPage = 20
    private var loadTask: Task<Void, Never>?

    // TODO(EPAC-299): Replace with the deployed member-speeches Lambda URL from AWS API Gateway.
    // Run: cd backend && make create-api SERVICE=member-speeches, then update this constant.
    private static let apiBase = URL(string: "https://placeholder.execute-api.us-east-1.amazonaws.com/production")!

    init(memberId: Int) {
        self.memberId = memberId
    }

    func selectTopic(_ topic: String?) {
        selectedTopic = topic
        loadTask?.cancel()
        loadTask = Task { await loadFirstPage() }
    }

    func loadFirstPage() async {
        currentPage = 0
        speeches = []
        hasMore = true
        errorMessage = nil
        await loadNextPage()
    }

    func loadNextPage() async {
        guard !isLoading, hasMore, memberId > 0 else { return }
        isLoading = true
        defer { isLoading = false }

        let nextPage = currentPage + 1
        guard var components = URLComponents(
            url: Self.apiBase.appending(path: "members/\(memberId)/speeches"),
            resolvingAgainstBaseURL: false
        ) else { return }

        var items = [
            URLQueryItem(name: "page", value: "\(nextPage)"),
            URLQueryItem(name: "per_page", value: "\(perPage)"),
        ]
        if let topic = selectedTopic {
            items.append(URLQueryItem(name: "topic", value: topic))
        }
        components.queryItems = items
        guard let url = components.url else { return }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                errorMessage = "Server error — check that the member-speeches Lambda is deployed."
                return
            }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let page = try decoder.decode(SpeechFeedPage.self, from: data)
            if nextPage == 1 { stats = page.stats }
            speeches.append(contentsOf: page.speeches)
            currentPage = page.page
            hasMore = page.page < page.pages
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - View

struct MemberSpeechFeedView: View {

    let member: ParliamentMember
    @State private var viewModel: MemberSpeechFeedViewModel

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var fetch: Fetch

    @State private var targetHansard: Hansard?
    @State private var targetSubject: SubjectOfBusiness?
    @State private var isLoadingSitting = false

    private static let isoDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    init(member: ParliamentMember) {
        self.member = member
        _viewModel = State(initialValue: MemberSpeechFeedViewModel(memberId: member.memberID))
    }

    var body: some View {
        Group {
            if member.memberID == 0 {
                unavailableView(message: "Member profile not fully loaded. Browse the calendar to trigger a sync.")
            } else if let err = viewModel.errorMessage, viewModel.speeches.isEmpty {
                unavailableView(message: err)
            } else {
                contentList
            }
        }
        .navigationTitle("Speeches")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $targetHansard) { hansard in
            SittingView(hansard: hansard, selectedSubject: $targetSubject)
                .environmentObject(fetch)
        }
        .task { await viewModel.loadFirstPage() }
    }

    // MARK: - Content

    private var contentList: some View {
        List {
            if let s = viewModel.stats {
                statsBar(s)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }

            topicFilterRow
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

            if viewModel.speeches.isEmpty && viewModel.isLoading {
                loadingRow
            } else {
                ForEach(viewModel.speeches) { entry in
                    Button { Task { await navigateToSpeech(entry) } } label: {
                        SpeechEntryRow(entry: entry)
                    }
                    .foregroundStyle(.primary)
                    .disabled(isLoadingSitting)
                }

                if viewModel.hasMore {
                    loadMoreRow
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if isLoadingSitting {
                ZStack {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    ProgressView("Loading sitting…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    // MARK: - Stats bar

    private func statsBar(_ s: MemberSpeechStats) -> some View {
        HStack(spacing: 0) {
            statCell(value: "\(s.totalSpeeches)", label: "speeches")
            if s.avgWordCount > 0 {
                Divider().frame(height: 30)
                statCell(value: "\(s.avgWordCount)", label: "avg words")
            }
            if !s.topTopic.isEmpty {
                Divider().frame(height: 30)
                statCell(value: s.topTopic.prefix(20).description, label: "most on")
            }
        }
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.bold().monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }

    // MARK: - Topic filter chips

    private var topicFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                topicChip(label: "All", count: nil, isSelected: viewModel.selectedTopic == nil) {
                    viewModel.selectTopic(nil)
                }
                ForEach(viewModel.topicCounts.prefix(12), id: \.topic) { item in
                    topicChip(label: item.topic, count: item.count,
                               isSelected: viewModel.selectedTopic == item.topic) {
                        viewModel.selectTopic(item.topic)
                    }
                }
                if viewModel.isLoading && viewModel.speeches.isEmpty {
                    ProgressView().scaleEffect(0.7)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
    }

    private func topicChip(label: String, count: Int?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label)
                    .lineLimit(1)
                if let count {
                    Text("(\(count))")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isSelected ? Color.accentColor : Color(.tertiarySystemBackground))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .accessibilityLabel(count.map { "\(label), \($0) speeches" } ?? label)
    }

    // MARK: - Rows

    private var loadingRow: some View {
        HStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .padding()
        .listRowSeparator(.hidden)
    }

    private var loadMoreRow: some View {
        Color.clear
            .frame(height: 1)
            .listRowSeparator(.hidden)
            .task { await viewModel.loadNextPage() }
    }

    private func unavailableView(message: String) -> some View {
        ContentUnavailableView {
            Label("Speeches Unavailable", systemImage: "text.bubble")
        } description: {
            Text(message)
        }
    }

    // MARK: - Navigation

    private func navigateToSpeech(_ entry: MemberSpeechEntry) async {
        guard let dateStr = entry.sittingDate,
              let date = Self.isoDate.date(from: dateStr) else { return }

        isLoadingSitting = true
        defer { isLoadingSitting = false }

        // Try local SwiftData first
        if let hansard = findHansard(for: date) {
            targetHansard = hansard
            return
        }

        // Download and retry
        try? await fetch.downloadHansard(date)
        if let hansard = findHansard(for: date) {
            targetHansard = hansard
        }
    }

    private func findHansard(for date: Date) -> Hansard? {
        let all = (try? modelContext.fetch(FetchDescriptor<Hansard>())) ?? []
        return all.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }
}

// MARK: - Speech entry row

private struct SpeechEntryRow: View {
    let entry: MemberSpeechEntry

    private static let isoDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private var formattedDate: String? {
        guard let s = entry.sittingDate,
              let d = Self.isoDate.date(from: s) else { return nil }
        return d.formatted(date: .abbreviated, time: .omitted)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                if let date = formattedDate {
                    Text(date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let wc = entry.wordCount, wc > 0 {
                    Text("\(wc) words")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if let subject = entry.subjectTitle, !subject.isEmpty {
                Text(subject)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
            }

            Text(entry.preview)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel([
            formattedDate,
            entry.subjectTitle,
            entry.preview,
            entry.wordCount.map { "\($0) words" },
        ].compactMap { $0 }.joined(separator: ", "))
    }
}
