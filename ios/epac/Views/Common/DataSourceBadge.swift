//
//  DataSourceBadge.swift
//  epac
//
//  Created on 2026-04-27.
//

import SwiftUI

/// A small pill badge showing the data source and approximate age of the data.
/// Amber when >24h old (daily-sync sources), red when >72h old.
/// Tap to open a sheet with the full source description and URL.
struct DataSourceBadge: View {
    let source: DataSource

    @State private var showDetail = false

    var body: some View {
        Button { showDetail = true } label: {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption2)
                Text(badgeText)
                    .font(.caption2.weight(.medium))
            }
            .foregroundStyle(badgeColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(badgeColor.opacity(0.12))
            .clipShape(Capsule())
        }
        .accessibilityLabel("\(source.name) — \(badgeText)")
        .accessibilityHint("Opens source details")
        .sheet(isPresented: $showDetail) {
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
        if age < 3600 {
            return "\(source.name) · \(Int(age / 60))m ago"
        } else if age < 86400 {
            return "\(source.name) · \(Int(age / 3600))h ago"
        } else {
            return "\(source.name) · \(Int(age / 86400))d ago"
        }
    }

    private var badgeColor: Color {
        guard let age = ageSeconds, let threshold = source.stalenessThreshold else {
            return Color.secondary
        }
        if age > threshold * 3 { return Color.red }
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
            stalenessThreshold: 86400   // amber after 24h
        )
    }

    static func votes(lastSync: Date? = nil) -> DataSource {
        DataSource(
            name: "Parliament of Canada",
            description: "Recorded votes from the House of Commons, published via the Parliament of Canada open data API (api.open.ourcommons.ca).",
            url: URL(string: "https://api.open.ourcommons.ca")!,
            lastSyncDate: lastSync ?? UserDefaults.standard.object(forKey: "epac.sync.votes") as? Date,
            vintage: nil,
            stalenessThreshold: 86400
        )
    }

    static func bills(lastSync: Date? = nil) -> DataSource {
        DataSource(
            name: "LEGISinfo",
            description: "Bill status and stage timelines from the Parliament of Canada LEGISinfo service.",
            url: URL(string: "https://www.parl.ca/LegisInfo/")!,
            lastSyncDate: lastSync ?? UserDefaults.standard.object(forKey: "epac.sync.bills") as? Date,
            vintage: nil,
            stalenessThreshold: 86400
        )
    }

    static func expenditures(lastSync: Date? = nil) -> DataSource {
        DataSource(
            name: "Proactive Disclosure",
            description: "MP travel, hospitality, and contract expenditures published quarterly by Parliament under the Proactive Disclosure rules.",
            url: URL(string: "https://www.ourcommons.ca/en/parliamentary-business/financial-transparency")!,
            lastSyncDate: lastSync ?? UserDefaults.standard.object(forKey: "epac.sync.expenditures") as? Date,
            vintage: nil,
            stalenessThreshold: 86400 * 7   // amber after 7 days (quarterly data)
        )
    }

    static func fiscalMonitor(lastSync: Date? = nil) -> DataSource {
        DataSource(
            name: "Finance Canada",
            description: "The Fiscal Monitor is the Department of Finance Canada's monthly statement of federal revenues, expenses, and the budgetary balance.",
            url: URL(string: "https://www.canada.ca/en/department-finance/services/publications/fiscal-monitor.html")!,
            lastSyncDate: lastSync ?? UserDefaults.standard.object(forKey: "epac.sync.fiscalMonitor") as? Date,
            vintage: nil,
            stalenessThreshold: 86400 * 45
        )
    }

    static func members(lastSync: Date? = nil) -> DataSource {
        DataSource(
            name: "Parliament of Canada",
            description: "MP profiles, ridings, and contact information from Parliament of Canada.",
            url: URL(string: "https://www.ourcommons.ca/members/en")!,
            lastSyncDate: lastSync ?? UserDefaults.standard.object(forKey: "epac.sync.members") as? Date,
            vintage: nil,
            stalenessThreshold: 86400 * 30  // amber after 30 days
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
}
