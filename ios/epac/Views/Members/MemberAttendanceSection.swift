//
//  MemberAttendanceSection.swift
//  epac
//
//  MP attendance record on the member profile (EPAC-897): how often an MP is
//  present for recorded divisions, with a Yea / Nay / Paired / Absent breakdown
//  and a national / party comparison. The figures are computed by
//  `LoadMPAttendance` from vote data already synced for the voting record
//  (EPAC-23) — no new ingestion, just a new lens on existing data.
//

import SwiftData
import SwiftUI

private enum AttendanceLayout {
    static let cardSpacing = EpacSpacing.s
    static let sectionSpacing = EpacSpacing.xs
    static let barHeight: CGFloat = 12
    static let barCornerRadius: CGFloat = 4
    static let legendSwatch: CGFloat = 10
    static let rowSpacing = EpacSpacing.xs
    static let arrowSpacing = EpacSpacing.xxs
}

/// Loads the attendance record for one MP and renders the card once available.
/// Mirrors `PartyLineScoreView`: an `@State` value filled by a `.task`, with the
/// card shown only when there is something to show.
struct MemberAttendanceSection: View {
    let member: ParliamentMember

    @Environment(\.modelContext) private var modelContext
    @State private var attendance: MPAttendance?

    var body: some View {
        Group {
            if let attendance {
                AttendanceRecordCard(member: member, attendance: attendance)
            }
        }
        .task(id: member.memberID) { await load() }
    }

    @MainActor
    private func load() async {
        attendance = nil
        let useCase = LoadMPAttendance(port: SwiftDataMPAttendanceAdapter(modelContext: modelContext))
        attendance = try? await useCase.execute(memberID: member.memberID)
    }
}

/// Presentation-only attendance card. Takes an already-computed `MPAttendance`,
/// so it renders without touching SwiftData and can be snapshot-tested directly.
struct AttendanceRecordCard: View {
    let member: ParliamentMember
    let attendance: MPAttendance

    @State private var showInfo = false

    private var record: AttendanceRecord { attendance.record }

    var body: some View {
        VStack(alignment: .leading, spacing: AttendanceLayout.cardSpacing) {
            header

            Text(String(format: NSLocalizedString("attendance.rate", comment: ""),
                        percent(record.attendanceRate)))
                .font(.title2.weight(.semibold))

            Text(denominatorText)
                .font(.caption2)
                .foregroundStyle(.secondary)

            breakdownBar
            legend

            if record.paired > 0 {
                Text(String(format: NSLocalizedString("attendance.paired.note", comment: ""), record.paired))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let comparison = attendance.comparison {
                comparisonSection(comparison)
            }

            sourceFooter
        }
        .padding()
        .background(Color.appSurface)
        .cornerRadius(EpacCornerRadius.m)
        .regularSizeClassFormSheet(isPresented: $showInfo) { infoSheet }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(NSLocalizedString("attendance.title", comment: ""))
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button { showInfo = true } label: {
                Image(systemName: "info.circle").foregroundStyle(.secondary)
            }
            .accessibilityLabel(NSLocalizedString("attendance.infoButton", comment: ""))
        }
    }

    private var denominatorText: String {
        if let start = record.denominatorStartDate {
            return String(format: NSLocalizedString("attendance.denominator.sinceDate", comment: ""),
                          record.present, record.totalDivisions,
                          start.formatted(date: .abbreviated, time: .omitted))
        }
        return String(format: NSLocalizedString("attendance.denominator.noDate", comment: ""),
                      record.present, record.totalDivisions)
    }

    // MARK: - Breakdown bar + legend

    // Colours come from the shared design-token palette. Unlike `Color.ballot`
    // (per-ballot colouring on the voting screen, where Paired is the amber
    // highlight), the attendance lens deliberately makes a *paired* absence
    // neutral and an *unexplained* absence the amber highlight — EPAC-897 requires
    // that pre-arranged pairings are not visually penalised like simply not
    // showing up.
    private var segments: [AttendanceSegment] {
        [
            AttendanceSegment(id: "yea", count: record.yea, color: .appPositive),
            AttendanceSegment(id: "nay", count: record.nay, color: .appDestructive),
            AttendanceSegment(id: "paired", count: record.paired, color: .appNeutral),
            AttendanceSegment(id: "absent", count: record.absent, color: .appWarning)
        ]
    }

    private var breakdownBar: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(segments) { segment in
                    segment.color
                        .frame(width: width(for: segment.count, in: geo.size.width))
                }
            }
        }
        .frame(height: AttendanceLayout.barHeight)
        .clipShape(RoundedRectangle(cornerRadius: AttendanceLayout.barCornerRadius))
        .accessibilityElement()
        .accessibilityLabel(String(format: NSLocalizedString("attendance.bar.accessibility", comment: ""),
                                   record.yea, record.nay, record.paired, record.absent, record.totalDivisions))
    }

    private func width(for count: Int, in total: CGFloat) -> CGFloat {
        guard record.totalDivisions > 0 else { return 0 }
        return total * CGFloat(count) / CGFloat(record.totalDivisions)
    }

    private var legend: some View {
        VStack(spacing: AttendanceLayout.rowSpacing) {
            legendRow(color: .appPositive, label: NSLocalizedString("attendance.legend.yea", comment: ""), count: record.yea)
            legendRow(color: .appDestructive, label: NSLocalizedString("attendance.legend.nay", comment: ""), count: record.nay)
            legendRow(color: .appNeutral, label: NSLocalizedString("attendance.legend.paired", comment: ""), count: record.paired)
            legendRow(color: .appWarning, label: NSLocalizedString("attendance.legend.absent", comment: ""), count: record.absent)
        }
    }

    private func legendRow(color: Color, label: String, count: Int) -> some View {
        HStack(spacing: EpacSpacing.xs) {
            Circle().fill(color)
                .frame(width: AttendanceLayout.legendSwatch, height: AttendanceLayout.legendSwatch)
            Text(label).font(.caption)
            Spacer()
            Text(count.formatted()).font(.caption.weight(.medium)).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(count)")
    }

    // MARK: - Comparison

    private func comparisonSection(_ comparison: AttendanceComparison) -> some View {
        VStack(alignment: .leading, spacing: AttendanceLayout.rowSpacing) {
            Divider()
            Text(NSLocalizedString("attendance.comparison.title", comment: ""))
                .font(.caption).foregroundStyle(.secondary)
            if let national = comparison.nationalAverageRate {
                comparisonRow(label: NSLocalizedString("attendance.comparison.national", comment: ""),
                              baseline: national)
            }
            if let party = comparison.partyAverageRate {
                comparisonRow(label: String(format: NSLocalizedString("attendance.comparison.party", comment: ""),
                                            member.party.shortName),
                              baseline: party)
            }
            Text(String(format: NSLocalizedString("attendance.comparison.method", comment: ""),
                        LoadMPAttendance.minimumDivisionsForComparison, comparison.nationalSampleSize))
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func comparisonRow(label: String, baseline: Double) -> some View {
        let above = record.attendanceRate >= baseline
        return HStack(spacing: AttendanceLayout.arrowSpacing) {
            Image(systemName: above ? "arrow.up" : "arrow.down")
                .font(.caption2)
                .foregroundStyle(above ? Color.appPositive : Color.appWarning)
            Text(label).font(.subheadline)
            Spacer()
            Text(String(format: NSLocalizedString("attendance.percent", comment: ""), percent(baseline)))
                .font(.subheadline.weight(.medium)).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(percent(baseline))%")
    }

    // MARK: - Source + info

    private var sourceFooter: some View {
        HStack(spacing: EpacSpacing.xxs) {
            Text(NSLocalizedString("attendance.source.prefix", comment: ""))
            Link(NSLocalizedString("attendance.source.title", comment: ""), destination: DataSource.votes().url)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private var infoSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: EpacSpacing.m) {
                    Text(NSLocalizedString("attendance.info.body", comment: ""))
                        .font(.body)
                }
                .padding()
            }
            .navigationTitle(NSLocalizedString("attendance.info.title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("attendance.info.done", comment: "")) { showInfo = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func percent(_ rate: Double) -> Int {
        Int((rate * 100).rounded())
    }
}

/// One coloured slice of the attendance breakdown bar.
private struct AttendanceSegment: Identifiable {
    let id: String
    let count: Int
    let color: Color
}
