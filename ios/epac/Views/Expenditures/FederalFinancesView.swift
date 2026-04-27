//
//  FederalFinancesView.swift
//  epac
//

import Charts
import SwiftData
import SwiftUI

struct FederalFinancesView: View {
	@EnvironmentObject private var fetch: Fetch
	@Environment(\.openURL) private var openURL
	@Query(sort: \FiscalMonitorEntry.month) private var entries: [FiscalMonitorEntry]
	@State private var isLoading = false
	@State private var loadFailed = false

	private var latest: FiscalMonitorEntry? { entries.last }

	var body: some View {
		Group {
			if isLoading && entries.isEmpty {
				ProgressView(NSLocalizedString("fiscalMonitor.loading", comment: ""))
			} else if loadFailed && entries.isEmpty {
				EmptyStateView(
					icon: "exclamationmark.triangle",
					title: NSLocalizedString("fiscalMonitor.error.title", comment: ""),
					message: NSLocalizedString("fiscalMonitor.error.description", comment: ""),
					action: EmptyStateAction(label: NSLocalizedString("Retry", comment: ""), handler: { Task { await load(force: true) } })
				)
			} else if entries.isEmpty {
				EmptyStateView(
					icon: "chart.line.uptrend.xyaxis",
					title: NSLocalizedString("fiscalMonitor.empty.title", comment: ""),
					message: NSLocalizedString("fiscalMonitor.empty.description", comment: ""),
					action: EmptyStateAction(label: NSLocalizedString("Retry", comment: ""), handler: { Task { await load(force: true) } })
				)
			} else {
				List {
					if let latest {
						Section {
							latestSummary(latest)
						}
					}

					Section(NSLocalizedString("fiscalMonitor.chart.title", comment: "")) {
						balanceChart
							.frame(height: 220)
							.padding(.vertical, 8)
					}

					Section(NSLocalizedString("fiscalMonitor.monthly.title", comment: "")) {
						ForEach(entries) { entry in
							monthlyRow(entry)
						}
					}

					Section(NSLocalizedString("fiscalMonitor.source.title", comment: "")) {
						if let latest {
							Button { openURL(latest.sourceURL) } label: {
								Label(latest.sourceTitle, systemImage: "arrow.up.right.square")
							}
							Text(String(format: NSLocalizedString("fiscalMonitor.published", comment: ""), latest.publicationDate.formatted(date: .abbreviated, time: .omitted)))
								.font(.caption)
								.foregroundStyle(.secondary)
						}
					}
				}
				.listStyle(.insetGrouped)
				.refreshable { await load(force: true) }
			}
		}
		.navigationTitle(NSLocalizedString("fiscalMonitor.navTitle", comment: ""))
		.navigationBarTitleDisplayMode(.large)
		.task { await load(force: false) }
	}

	private func latestSummary(_ entry: FiscalMonitorEntry) -> some View {
		VStack(alignment: .leading, spacing: 10) {
			HStack {
				VStack(alignment: .leading, spacing: 2) {
					Text(entry.month, format: .dateTime.month(.wide).year())
						.font(.headline)
					Text(entry.fiscalYear)
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				Spacer()
				Text(Self.formatMillions(entry.budgetaryBalanceMillions))
					.font(.headline)
					.foregroundStyle(entry.budgetaryBalanceMillions >= 0 ? .green : .red)
			}
			HStack {
				metric(NSLocalizedString("fiscalMonitor.revenue", comment: ""), entry.revenueMillions, .green)
				metric(NSLocalizedString("fiscalMonitor.expenses", comment: ""), entry.expenseMillions, .orange)
				metric(NSLocalizedString("fiscalMonitor.ytd", comment: ""), entry.yearToDateBalanceMillions, entry.yearToDateBalanceMillions >= 0 ? .green : .red)
			}
			if entry.isBudgetVarianceAlert {
				Label(NSLocalizedString("fiscalMonitor.alert", comment: ""), systemImage: "exclamationmark.triangle.fill")
					.font(.caption)
					.foregroundStyle(.orange)
			}
		}
		.padding(.vertical, 4)
	}

	private func metric(_ title: String, _ value: Double, _ color: Color) -> some View {
		VStack(alignment: .leading, spacing: 2) {
			Text(title)
				.font(.caption2)
				.foregroundStyle(.secondary)
			Text(Self.formatMillions(value))
				.font(.caption.bold())
				.foregroundStyle(color)
				.lineLimit(1)
				.minimumScaleFactor(0.75)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
	}

	private var balanceChart: some View {
		Chart(entries) { entry in
			BarMark(
				x: .value("Month", entry.month, unit: .month),
				y: .value("Monthly balance", entry.budgetaryBalanceMillions / 1_000)
			)
			.foregroundStyle(entry.budgetaryBalanceMillions >= 0 ? Color.green : Color.red)
			LineMark(
				x: .value("Month", entry.month, unit: .month),
				y: .value("Year to date", entry.yearToDateBalanceMillions / 1_000)
			)
			.foregroundStyle(Color.accentColor)
		}
		.chartYAxisLabel("CAD billions")
	}

	private func monthlyRow(_ entry: FiscalMonitorEntry) -> some View {
		VStack(alignment: .leading, spacing: 4) {
			HStack {
				Text(entry.month, format: .dateTime.month(.wide))
					.font(.subheadline)
				Spacer()
				Text(Self.formatMillions(entry.budgetaryBalanceMillions))
					.font(.subheadline.bold())
					.foregroundStyle(entry.budgetaryBalanceMillions >= 0 ? .green : .red)
			}
			Text(String(format: NSLocalizedString("fiscalMonitor.row.detail", comment: ""), entry.revenueMillions / 1_000, entry.expenseMillions / 1_000))
				.font(.caption)
				.foregroundStyle(.secondary)
		}
		.padding(.vertical, 2)
	}

	private func load(force: Bool) async {
		if !force && !entries.isEmpty { return }
		isLoading = true
		loadFailed = false
		do {
			if force {
				try await fetch.downloadFiscalMonitorEntries()
			} else {
				try await fetch.fiscalMonitorEntries()
			}
		} catch {
			loadFailed = entries.isEmpty
		}
		isLoading = false
	}

	private static func formatMillions(_ value: Double) -> String {
		let formatter = NumberFormatter()
		formatter.numberStyle = .currency
		formatter.currencyCode = "CAD"
		formatter.maximumFractionDigits = abs(value) >= 1_000 ? 1 : 0
		let scaled = value / 1_000
		let formatted = formatter.string(from: NSNumber(value: scaled)) ?? "$\(scaled)"
		return "\(formatted)B"
	}
}
