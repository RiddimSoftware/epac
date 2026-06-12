import SwiftUI

struct MemberBiographySection: View {
    let member: ParliamentMember
    private let loadBiography: LoadMPBiography
    @State private var biography: MemberBiography?
    @State private var isLoading = false

    init(
        member: ParliamentMember,
        loadBiography: LoadMPBiography = LoadMPBiography(repository: BackendMPBiographyRepository())
    ) {
        self.member = member
        self.loadBiography = loadBiography
    }

    var body: some View {
        Group {
            if let displayBiography = biography?.withFallbackServicePeriod(fallbackServicePeriod),
               displayBiography.hasDisplayContent {
                MemberBiographyCard(member: member, biography: displayBiography)
            } else if isLoading {
                loadingCard
            }
        }
        .task(id: member.memberID) {
            guard member.memberID > 0 else { return }
            isLoading = true
            defer { isLoading = false }
            biography = try? await loadBiography.execute(memberID: member.memberID)
        }
    }

    private var loadingCard: some View {
        HStack(spacing: MemberProfileLayout.inlineSpacing) {
            ProgressView().scaleEffect(MemberProfileLayout.loadingScale)
            Text("Loading biography")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(MemberProfileLayout.cardCornerRadius)
    }

    private var fallbackServicePeriod: ParliamentaryServicePeriod? {
        guard let fromDate = Self.dateFormatter.stringIfPresent(member.fromDateTime) else { return nil }
        return ParliamentaryServicePeriod(
            id: "member-\(member.memberID)-service",
            label: member.toDateTime == nil ? "Current term" : "Term",
            fromDate: fromDate,
            toDate: Self.dateFormatter.stringIfPresent(member.toDateTime)
        )
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_CA")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

struct MemberBiographyCard: View {
    let member: ParliamentMember
    let biography: MemberBiography

    var body: some View {
        VStack(alignment: .leading, spacing: MemberProfileLayout.biographyGroupSpacing) {
            HStack {
                Label("Biography", systemImage: "person.text.rectangle")
                    .font(.headline)
                Spacer()
            }

            if !biography.yearsServed.isEmpty {
                biographyList(title: "Years served", values: biography.yearsServed.map(\.displayText))
            }
            if !biography.previousRoles.isEmpty {
                biographyList(title: "Previous roles", values: biography.previousRoles.map(\.displayText))
            }
            if !biography.education.isEmpty {
                biographyList(title: "Education", values: biography.education)
            }
            if !biography.professionalBackground.isEmpty {
                biographyList(title: "Professional background", values: biography.professionalBackground)
            }
            if !biography.sponsoredBills.isEmpty {
                sponsoredBillsSection
            }
            sourceFooter
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(MemberProfileLayout.cardCornerRadius)
        .accessibilityIdentifier("mp-biography-section")
    }

    private func biographyList(title: String, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: MemberProfileLayout.compactTextSpacing) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var sponsoredBillsSection: some View {
        VStack(alignment: .leading, spacing: MemberProfileLayout.biographyRowSpacing) {
            Text("Private Members' Bills sponsored")
                .font(.subheadline.weight(.semibold))
            ForEach(biography.sponsoredBills.prefix(MemberProfileLayout.biographyBillLimit)) { bill in
                sponsoredBillLink(bill)
            }
            NavigationLink(
                destination: BillsView(
                    billNumbersFilter: Set(biography.sponsoredBills.map(\.number)),
                    navigationTitle: "Sponsored Bills"
                )
            ) {
                HStack {
                    Label("Bills sponsored by this MP", systemImage: "doc.text.magnifyingglass")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.caption)
            .foregroundStyle(.primary)
        }
    }

    @ViewBuilder
    private func sponsoredBillLink(_ bill: SponsoredBillReference) -> some View {
        if let url = bill.legisInfoURL {
            Link(bill.displayTitle, destination: url)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(bill.displayTitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var sourceFooter: some View {
        let sourceURL = biography.officialProfileURL ?? biography.sourceURL ?? member.websiteURL
        if let sourceURL {
            HStack(spacing: MemberProfileLayout.biographyFooterSpacing) {
                Text("Source:")
                Link("Parliament.ca", destination: sourceURL)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}

private extension DateFormatter {
    func stringIfPresent(_ date: Date?) -> String? {
        guard let date else { return nil }
        return string(from: date)
    }
}
