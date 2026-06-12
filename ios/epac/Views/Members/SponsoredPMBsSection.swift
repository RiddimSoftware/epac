//
//  SponsoredPMBsSection.swift
//  epac
//
//  Shows a list of Private Members' Bills sponsored by the member on their profile.
//

import SwiftUI

private enum SponsoredPMBsLayout {
    static let sectionSpacing: CGFloat = 12
    static let previewLimit = 5
    static let contentTopPadding = EpacSpacing.s
    static let cardCornerRadius = EpacCornerRadius.m
    static let rowSpacing = EpacSpacing.xs
    static let rowVerticalPadding = EpacSpacing.xs
}

struct SponsoredPMBsSection: View {
    let member: ParliamentMember

    @State private var sponsoredPMBs: [Bill] = []
    @State private var isLoading = false
    @State private var isExpanded = true

    var body: some View {
        if !sponsoredPMBs.isEmpty {
            DisclosureGroup(
                isExpanded: $isExpanded,
                content: {
                    VStack(alignment: .leading, spacing: SponsoredPMBsLayout.sectionSpacing) {
                        ForEach(sponsoredPMBs.prefix(SponsoredPMBsLayout.previewLimit)) { bill in
                            NavigationLink(destination: BillDetailView(bill: bill)) {
                                SponsoredPMBRow(bill: bill)
                            }
                            .buttonStyle(.plain)
                        }
                        if sponsoredPMBs.count > SponsoredPMBsLayout.previewLimit {
                            let format = NSLocalizedString("member.sponsoredPMBs.more", comment: "")
                            let count = sponsoredPMBs.count - SponsoredPMBsLayout.previewLimit
                            Text(String(format: format, count))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, SponsoredPMBsLayout.contentTopPadding)
                },
                label: {
                    HStack {
                        Image(systemName: "doc.text.fill")
                            .foregroundStyle(.tint)
                        Text(NSLocalizedString("member.sponsoredPMBs.title", comment: ""))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                        Text("\(sponsoredPMBs.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color(.systemGray5))
                            .clipShape(Capsule())
                    }
                }
            )
            .padding()
            .background(Color.appSurface)
            .cornerRadius(SponsoredPMBsLayout.cardCornerRadius)
            .task {
                await loadSponsoredBills()
            }
        } else {
            Color.clear
                .frame(height: 0)
                .task {
                    await loadSponsoredBills()
                }
        }
    }

    private func loadSponsoredBills() async {
        guard sponsoredPMBs.isEmpty && !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let allBills = try await BillsService.fetchBills()
            let filtered = allBills.filter { bill in
                // Check if it's a PMB
                let isPMB = bill.type == .privateMember || bill.type == .senatePublic || bill.type == .senatePrivate
                guard isPMB else { return false }

                // Match sponsor
                let parts = bill.sponsorName.components(separatedBy: " ")
                let lastName = parts.last ?? ""
                return member.lastName.localizedCaseInsensitiveCompare(lastName) == .orderedSame &&
                    bill.sponsorName.localizedCaseInsensitiveContains(member.firstName.prefix(3))
            }
            // Sort by introducedDate (newest first)
            self.sponsoredPMBs = filtered.sorted {
                ($0.introducedDate ?? .distantPast) > ($1.introducedDate ?? .distantPast)
            }
        } catch {
            // Fail silently
        }
    }
}

private struct SponsoredPMBRow: View {
    let bill: Bill

    var body: some View {
        VStack(alignment: .leading, spacing: SponsoredPMBsLayout.rowSpacing) {
            HStack {
                Text(bill.number)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                BillStatusBadge(status: bill.status)
            }
            Text(bill.title)
                .font(.subheadline)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .foregroundStyle(.primary)
            if let introduced = bill.introducedDate {
                let format = NSLocalizedString("member.sponsoredPMBs.introduced", comment: "")
                let dateStr = introduced.formatted(date: .abbreviated, time: .omitted)
                Text(String(format: format, dateStr))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, SponsoredPMBsLayout.rowVerticalPadding)
        .contentShape(Rectangle())
    }
}
