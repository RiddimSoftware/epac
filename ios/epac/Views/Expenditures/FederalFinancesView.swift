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
	@Query(sort: \FiscalMonitorEntry.periodDate) private var entries: [FiscalMonitorEntry]
	@State private var isLoading = false
	@State private var loadFailed = false

	private var currentFiscalYearEntries: [FiscalMonitorEntry] {
		guard let latestFiscalYear = entries.map(\.fiscalYearStart).max() else { return [] }
		return entries
			.filter { $0.fiscalYearStart == latestFiscalYear }
			.sorted { $0.periodDate < $1.periodDate }
	}

	private var latestEntry: FiscalMonitorEntry? {
		currentFiscalYearEntries.last
	}

	var body: some View {
		ZStack(alignment: .bottomTrailing) {
			content
			DataSourceBadge(source: .fiscalMonitor())
				.padding()
		}
		.navigationTitle("Federal Finances")
		.navigationBarTitleDisplayMode(.inline)
		.task {
			await loadFiscalMonitor()
		}
		.refreshable {
			await refreshFiscalMonitor()
		}
	}

	@ViewBuilder
	private var content: some View {
		if currentFiscalYearEntries.isEmpty && isLoading {
			ProgressView("Fetching Finance Canada data...")
				.frame(maxWidth: .infinity, maxHeight: .infinity)
		} else if currentFiscalYearEntries.isEmpty && loadFailed {
			ContentUnavailableView {
				Label("Couldn't Load Fiscal Monitor", systemImage: "exclamationmark.triangle")
			} description: {
				Text("Check your connection and try again.")
			} actions: {
				Button("Retry") {
					Task { await refreshFiscalMonitor() }
				}
				.buttonStyle(.borderedProminent)
			}
		} else {
			List {
				if let latestEntry {
					Section {
						summaryCard(latestEntry)
					}
				}

				Section("Monthly Budgetary Balance") {
					balanceChart
						.frame(height: 220)
						.listRowInsets(EdgeInsets(top: 14, leading: 12, bottom: 14, trailing: 12))
					Text("Positive values are surpluses. Negative values are deficits. Amounts are shown in billions of Canadian dollars.")
						.font(.caption)
						.foregroundStyle(.secondary)
				}

				Section("Revenue and Spending") {
					revenueSpendingChart
						.frame(height: 220)
						.listRowInsets(EdgeInsets(top: 14, leading: 12, bottom: 14, trailing: 12))
				}

				Section("Monthly Results") {
					ForEach(currentFiscalYearEntries) { entry in
						monthlyRow(entry)
					}
				}

				if let latestEntry {
					Section("Official Source") {
						Button {
							if let url = URL(string: latestEntry.sourceURL) {
								openURL(url)
							}
						} label: {
							HStack(spacing: 12) {
								Image(systemName: "checkmark.seal.fill")
									.foregroundStyle(.green)
									.frame(width: 28)
								VStack(alignment: .leading, spacing: 2) {
									Text(latestEntry.sourceTitle)
										.font(.subheadline)
										.foregroundStyle(.primary)
									Text("Published \(latestEntry.publicationDate.formatted(date: .abbreviated, time: .omitted))")
										.font(.caption)
										.foregroundStyle(.secondary)
								}
								Spacer()
								Image(systemName: "arrow.up.right.square")
									.font(.caption)
									.foregroundStyle(.tertiary)
							}
						}
					}
				}
			}
			.listStyle(.insetGrouped)
		}
	}

	private func summaryCard(_ entry: FiscalMonitorEntry) -> some View {
		VStack(alignment: .leading, spacing: 14) {
			HStack(alignment: .top) {
				VStack(alignment: .leading, spacing: 4) {
					Text("\(entry.monthName) \(Calendar.current.component(.year, from: entry.periodDate))")
						.font(.headline)
					Text("Fiscal year \(entry.fiscalYearStart)-\(String(entry.fiscalYearStart + 1).suffix(2))")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				Spacer()
				balancePill(entry.budgetaryBalanceMillions)
			}

			HStack(spacing: 12) {
				metricTile(title: "Revenue", value: entry.revenueMillions)
				metricTile(title: "Spending", value: entry.totalSpendingMillions)
			}

			if let projection = entry.annualBudgetProjectionMillions {
				Divider()
				HStack {
					Text("Year-to-date balance")
					Spacer()
					Text(formatCurrencyMillions(entry.yearToDateBudgetaryBalanceMillions))
						.fontWeight(.semibold)
				}
				HStack {
					Text("Budget projection")
					Spacer()
					Text(formatCurrencyMillions(projection))
						.fontWeight(.semibold)
				}
				.font(.subheadline)
				.foregroundStyle(.secondary)

				if abs(entry.yearToDateBudgetaryBalanceMillions) > abs(projection) * 1.05 {
					Label("Year-to-date deficit has exceeded the annual budget projection by over 5%.", systemImage: "exclamationmark.triangle.fill")
						.font(.caption)
						.foregroundStyle(.orange)
				}
			}
		}
		.padding(.vertical, 4)
	}

	private var balanceChart: some View {
		Chart(currentFiscalYearEntries) { entry in
			BarMark(
				x: .value("Month", entry.monthName),
				y: .value("Balance", entry.budgetaryBalanceMillions / 1_000)
			)
			.foregroundStyle(entry.budgetaryBalanceMillions >= 0 ? Color.green : Color.red)
		}
		.chartYAxisLabel("$B")
	}

	private var revenueSpendingChart: some View {
		Chart {
			ForEach(currentFiscalYearEntries) { entry in
				LineMark(
					x: .value("Month", entry.monthName),
					y: .value("Revenue", entry.revenueMillions / 1_000),
					series: .value("Type", "Revenue")
				)
				.foregroundStyle(.green)

				LineMark(
					x: .value("Month", entry.monthName),
					y: .value("Spending", entry.totalSpendingMillions / 1_000),
					series: .value("Type", "Spending")
				)
				.foregroundStyle(.blue)
			}
		}
		.chartYAxisLabel("$B")
	}

	private func monthlyRow(_ entry: FiscalMonitorEntry) -> some View {
		HStack {
			VStack(alignment: .leading, spacing: 3) {
				Text(entry.monthName)
					.font(.subheadline)
				Text("Published \(entry.publicationDate.formatted(date: .abbreviated, time: .omitted))")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			Spacer()
			VStack(alignment: .trailing, spacing: 3) {
				Text(formatCurrencyMillions(entry.budgetaryBalanceMillions))
					.font(.subheadline.weight(.semibold))
					.foregroundStyle(entry.budgetaryBalanceMillions >= 0 ? .green : .red)
				Text("YTD \(formatCurrencyMillions(entry.yearToDateBudgetaryBalanceMillions))")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
	}

	private func metricTile(title: String, value: Double) -> some View {
		VStack(alignment: .leading, spacing: 4) {
			Text(title)
				.font(.caption)
				.foregroundStyle(.secondary)
			Text(formatCurrencyMillions(value))
				.font(.headline)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
	}

	private func balancePill(_ value: Double) -> some View {
		Text(formatCurrencyMillions(value))
			.font(.caption.weight(.semibold))
			.foregroundStyle(value >= 0 ? .green : .red)
			.padding(.horizontal, 10)
			.padding(.vertical, 5)
			.background((value >= 0 ? Color.green : Color.red).opacity(0.12))
			.clipShape(Capsule())
	}

	private func formatCurrencyMillions(_ value: Double) -> String {
		let billions = value / 1_000
		let prefix = billions < 0 ? "-$" : "$"
		return "\(prefix)\(String(format: "%.1f", abs(billions)))B"
	}

	@MainActor
	private func loadFiscalMonitor() async {
		guard currentFiscalYearEntries.isEmpty else { return }
		await refreshFiscalMonitor()
	}

	@MainActor
	private func refreshFiscalMonitor() async {
		isLoading = true
		loadFailed = false
		do {
			try await fetch.fiscalMonitorEntries()
		} catch {
			Log.error("Failed to load Fiscal Monitor: \(error.localizedDescription)")
			loadFailed = true
		}
		isLoading = false
	}
}
