//
//  DataSourceBadge.swift
//  epac
//
//  Created on 2026-04-27.
//

import SwiftUI

private enum DataSourceBadgeLayout {
    static let spacing = EpacSpacing.xs
    static let horizontalPadding = EpacSpacing.s
    static let verticalPadding: CGFloat = 3
    static let badgeOpacity = EpacOpacity.tint
}

private enum DataSourceTiming {
    static let secondsPerMinute: TimeInterval = 60
    static let secondsPerHour: TimeInterval = 3_600
    static let secondsPerDay: TimeInterval = 86_400
    static let staleMultiplier: TimeInterval = 3
    static let weeklyMultiplier: TimeInterval = 7
    static let fiscalMonitorMultiplier: TimeInterval = 45
    static let membersMultiplier: TimeInterval = 30
}

/// A small pill badge showing the data source and approximate age of the data.
/// Amber when >24h old (daily-sync sources), red when >72h old.
/// Tap to open a sheet with the full source description and URL.
struct DataSourceBadge: View {
    let source: DataSource

    @State private var showDetail = false

    var body: some View {
        Button { showDetail = true } label: {
            HStack(spacing: DataSourceBadgeLayout.spacing) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption2)
                Text(badgeText)
                    .font(.caption2.weight(.medium))
            }
            .foregroundStyle(badgeColor)
            .padding(.horizontal, DataSourceBadgeLayout.horizontalPadding)
            .padding(.vertical, DataSourceBadgeLayout.verticalPadding)
            .background(badgeColor.opacity(DataSourceBadgeLayout.badgeOpacity))
            .clipShape(Capsule())
        }
        .accessibilityLabel("\(source.name) — \(badgeText)")
        .accessibilityHint("Opens source details")
        .regularSizeClassFormSheet(isPresented: $showDetail) {
            DataSourceDetailSheet(source: source)
        }
    }

    private var ageSeconds: TimeInterval? {
        guard let last = source.lastSyncDate else { return nil }
        return Date().timeIntervalSince(last)
    }

    private var badgeText: String {
        guard let age = ageSeconds else {
            return source.vintage ?? source.name
        }
        if age < DataSourceTiming.secondsPerHour {
            return "\(source.name) · \(Int(age / DataSourceTiming.secondsPerMinute))m ago"
        } else if age < DataSourceTiming.secondsPerDay {
            return "\(source.name) · \(Int(age / DataSourceTiming.secondsPerHour))h ago"
        } else {
            return "\(source.name) · \(Int(age / DataSourceTiming.secondsPerDay))d ago"
        }
    }

    private var badgeColor: Color {
        guard let age = ageSeconds, let threshold = source.stalenessThreshold else {
            return Color.secondary
        }
        if age > threshold * DataSourceTiming.staleMultiplier { return Color.red }
        if age > threshold { return Color.orange }
        return Color.secondary
    }
}

struct DataSourceDetailSheet: View {
    let source: DataSource
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent(NSLocalizedString("dataSource.source", comment: ""), value: source.name)
                    if let vintage = source.vintage {
                        LabeledContent(NSLocalizedString("dataSource.vintage", comment: ""), value: vintage)
                    }
                    if let last = source.lastSyncDate {
                        LabeledContent(NSLocalizedString("dataSource.updated", comment: ""),
                                      value: last.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                Section {
                    Text(source.description)
                        .font(.body)
                }
                Section {
                    Link(NSLocalizedString("dataSource.viewSource", comment: ""),
                         destination: source.url)
                        .foregroundStyle(.tint)
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            .navigationBarTitleDisplayMode(.inline)
            #else
            .listStyle(.inset)
            #endif
            .navigationTitle(source.name)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("dataSource.done", comment: "")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// Describes a government data source for display in the badge.
struct DataSource {
    let name: String          // Short name: "Hansard", "Elections Canada"
    let description: String   // 1–2 sentence explanation
    let url: URL              // Canonical source URL
    let lastSyncDate: Date?   // When this data type was last fetched; nil = use vintage
    let vintage: String?      // Static label: "2021 Census"; nil = use lastSyncDate
    let stalenessThreshold: TimeInterval?  // nil = no staleness colouring

    // MARK: - Predefined sources

    static func hansard(lastSync: Date? = nil) -> DataSource {
        DataSource(
            name: "Hansard",
            description: "The verbatim record of every word spoken in the House of Commons, published by Parliament of Canada within hours of each sitting.",
            url: URL(string: "https://www.ourcommons.ca/en/parliamentary-business/house-publications/")!,
            lastSyncDate: lastSync ?? UserDefaults.standard.object(forKey: "epac.sync.hansard") as? Date,
            vintage: nil,
            stalenessThreshold: DataSourceTiming.secondsPerDay   // amber after 24h
        )
    }

    static func votes(lastSync: Date? = nil) -> DataSource {
        DataSource(
            name: "Parliament of Canada",
            description: "Recorded votes from the House of Commons, published via the Parliament of Canada open data API (api.openparliament.ca).",
            url: URL(string: "https://api.openparliament.ca")!,
            lastSyncDate: lastSync ?? UserDefaults.standard.object(forKey: "epac.sync.votes") as? Date,
            vintage: nil,
            stalenessThreshold: DataSourceTiming.secondsPerDay
        )
    }

    static func bills(lastSync: Date? = nil) -> DataSource {
        DataSource(
            name: "LEGISinfo",
            description: "Bill status and stage timelines from the Parliament of Canada LEGISinfo service.",
            url: URL(string: "https://www.parl.ca/LegisInfo/")!,
            lastSyncDate: lastSync ?? UserDefaults.standard.object(forKey: "epac.sync.bills") as? Date,
            vintage: nil,
            stalenessThreshold: DataSourceTiming.secondsPerDay
        )
    }

    static func expenditures(lastSync: Date? = nil) -> DataSource {
        DataSource(
            name: "Proactive Disclosure",
            description: "MP travel, hospitality, and contract expenditures published quarterly by Parliament under the Proactive Disclosure rules.",
            url: URL(string: "https://www.ourcommons.ca/en/parliamentary-business/financial-transparency")!,
            lastSyncDate: lastSync ?? UserDefaults.standard.object(forKey: "epac.sync.expenditures") as? Date,
            vintage: nil,
            stalenessThreshold: DataSourceTiming.secondsPerDay * DataSourceTiming.weeklyMultiplier   // amber after 7 days (quarterly data)
        )
    }

    static func fiscalMonitor(lastSync: Date? = nil) -> DataSource {
        DataSource(
            name: "Finance Canada",
            description: "The Fiscal Monitor is the Department of Finance Canada's monthly statement of federal revenues, expenses, and the budgetary balance.",
            url: URL(string: "https://www.canada.ca/en/department-finance/services/publications/fiscal-monitor.html")!,
            lastSyncDate: lastSync ?? UserDefaults.standard.object(forKey: "epac.sync.fiscalMonitor") as? Date,
            vintage: nil,
            stalenessThreshold: DataSourceTiming.secondsPerDay * DataSourceTiming.fiscalMonitorMultiplier
        )
    }

    static func members(lastSync: Date? = nil) -> DataSource {
        DataSource(
            name: "Parliament of Canada",
            description: "MP profiles, ridings, and contact information from Parliament of Canada.",
            url: URL(string: "https://www.ourcommons.ca/members/en")!,
            lastSyncDate: lastSync ?? UserDefaults.standard.object(forKey: "epac.sync.members") as? Date,
            vintage: nil,
            stalenessThreshold: DataSourceTiming.secondsPerDay * DataSourceTiming.membersMultiplier  // amber after 30 days
        )
    }

    static var lobbyist: DataSource {
        DataSource(
            name: "Commissioner of Lobbying",
            description: "Registered communications between lobbyists and designated public office holders, published by the Commissioner of Lobbying of Canada.",
            url: URL(string: "https://lobbycanada.gc.ca")!,
            lastSyncDate: nil,
            vintage: "Current Parliament",
            stalenessThreshold: nil
        )
    }

    static func reconciliationCalls() -> DataSource {
        DataSource(
            name: "Yellowhead/CBC",
            description: "Truth and Reconciliation Commission Calls to Action status baseline from Yellowhead Institute, with per-call implementation phases and detail links from CBC Beyond 94.",
            url: URL(string: "https://yellowheadinstitute.org/report/trc/")!,
            lastSyncDate: nil,
            vintage: "Reviewed 2026",
            stalenessThreshold: nil
        )
    }

    static func cppOas() -> DataSource {
        DataSource(
            name: "ESDC",
            description: "Canada Pension Plan and Old Age Security recipient counts by province, published monthly by Employment and Social Development Canada on open.canada.ca.",
            url: URL(string: "https://www.canada.ca/en/employment-social-development/programs/pensions/reports/statistical-bulletin.html")!,
            lastSyncDate: nil,
            vintage: "Monthly — ESDC",
            stalenessThreshold: nil
        )
    }

    static func veteransAffairs() -> DataSource {
        DataSource(
            name: "VAC",
            description: "Veterans Affairs Canada Facts and Figures, Departmental Results Reports, and disability-benefit processing reports. Provincial figures are Veteran population counts from the 2021 Census; benefit and wait-time figures are national.",
            url: URL(string: "https://www.veterans.gc.ca/en/news-and-media/facts-and-figures")!,
            lastSyncDate: nil,
            vintage: "VAC reports",
            stalenessThreshold: nil
        )
    }

    static func studentFinance() -> DataSource {
        DataSource(
            name: "ESDC / StatCan",
            description: "Canada Student Financial Assistance Program loan and repayment-assistance statistics from ESDC, combined with Statistics Canada undergraduate tuition fees by province.",
            url: URL(string: "https://www.canada.ca/en/employment-social-development/programs/canada-student-loans-grants/reports/student-financial-assistance-statistics-2023-2024.html")!,
            lastSyncDate: nil,
            vintage: "Annual",
            stalenessThreshold: nil
        )
    }

    static func transportSafety() -> DataSource {
        DataSource(
            name: "TSB / Transport Canada",
            description: "Air, marine, and rail occurrence counts from Transportation Safety Board annual statistics, with road casualty rates from Transport Canada's National Collision Database.",
            url: URL(string: "https://tsb.gc.ca/eng/stats/aviation/stats.html")!,
            lastSyncDate: nil,
            vintage: "2023-2024",
            stalenessThreshold: nil
        )
    }

    static func naturalResources() -> DataSource {
        DataSource(
            name: "NRCan",
            description: "Natural Resources Canada Canadian Minerals Yearbook tables and National Forestry Database harvest and Crown timber revenue tables. Confidential mineral cells are suppressed by NRCan and shown as confidential in the app.",
            url: NaturalResourcesStatisticsDatabase.snapshot()?.source.url
                ?? NaturalResourcesStatisticsDatabase.fallbackSource.url,
            lastSyncDate: nil,
            vintage: "2025 minerals",
            stalenessThreshold: nil
        )
    }

    static func corrections() -> DataSource {
        DataSource(
            name: "CSC / OCI / StatCan",
            description: "Federal corrections statistics from Correctional Service Canada accountability reports, Office of the Correctional Investigator annual reports, and Statistics Canada Census population shares.",
            url: URL(string: "https://www.canada.ca/en/correctional-service/corporate/transparency/reporting/departmental-results-reports/2023-2024.html")!,
            lastSyncDate: nil,
            vintage: "Annual",
            stalenessThreshold: nil
        )
    }

    static func gicAppointments() -> DataSource {
        DataSource(
            name: "appointments.gc.ca",
            description: "Governor in Council appointee records from the Federal Organizations registry, with matched Privy Council Office Orders in Council and 2025-26 compensation ranges where published.",
            url: GICAppointmentsDatabase.snapshot()?.source.url
                ?? GICAppointmentsDatabase.fallbackSource.url,
            lastSyncDate: nil,
            vintage: GICAppointmentsDatabase.snapshot()?.retrievedAt ?? "Current snapshot",
            stalenessThreshold: nil
        )
    }
}
