//
//  FederalFinancesView.swift
//  epac
//

import Charts
import SwiftData
import SwiftUI

private enum FederalFinancesLayout {
	static let retryDelaySeconds: Int64 = 2
	static let chartHeight: CGFloat = 220
	static let rowInsetVertical: CGFloat = 14
	static let rowInsetHorizontal: CGFloat = 12
	static var chartInsets: EdgeInsets {
		EdgeInsets(
			top: rowInsetVertical,
			leading: rowInsetHorizontal,
			bottom: rowInsetVertical,
			trailing: rowInsetHorizontal
		)
	}
	static let sourceRowSpacing: CGFloat = 12
	static let sourceIconWidth: CGFloat = 28
	static let sourceTextSpacing = EpacSpacing.xxs
	static let summarySpacing: CGFloat = 14
	static let summaryHeaderSpacing = EpacSpacing.xs
	static let shortFiscalYearDigits = 2
	static let metricRowSpacing: CGFloat = 12
	static let projectionWarningMultiplier = 1.05
	static let compactVerticalPadding = EpacSpacing.xs
	static let millionsPerBillion = 1_000.0
	static let budgetRuleLineWidth: CGFloat = 2
	static let budgetRuleDashLength: CGFloat = 5
	static var budgetRuleDashPattern: [CGFloat] {
		[budgetRuleDashLength]
	}
	static let monthlyRowTextSpacing: CGFloat = 3
	static let metricTextSpacing = EpacSpacing.xs
	static let balancePillHorizontalPadding: CGFloat = 10
	static let balancePillVerticalPadding: CGFloat = 5
	static let balancePillOpacity = EpacOpacity.tint
}

struct FederalFinancesView: View {
	@EnvironmentObject private var fetch: Fetch
	@Environment(\.openURL) private var openURL
	@Query(sort: \FiscalMonitorEntry.periodDate) private var entries: [FiscalMonitorEntry]
	@State private var isLoading = false
	@State private var loadFailed = false
	@State private var isRetryDisabled = false

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
					guard !isRetryDisabled else { return }
					isRetryDisabled = true
					Task { try? await Task.sleep(for: .seconds(FederalFinancesLayout.retryDelaySeconds)); isRetryDisabled = false }
					Task { await refreshFiscalMonitor() }
				}
				.buttonStyle(.borderedProminent)
				.disabled(isRetryDisabled)
			}
		} else {
			List {
				if let latestEntry {
					Section {
						summaryCard(latestEntry)
					}
				}

				Section("Year-to-Date Balance vs Budget") {
					ytdBudgetChart
						.frame(height: FederalFinancesLayout.chartHeight)
						.listRowInsets(FederalFinancesLayout.chartInsets)
					Text("The line shows the running year-to-date budgetary balance. The budget marker is the annual projection from the Fiscal Monitor. Amounts are shown in billions of Canadian dollars.")
						.font(.caption)
						.foregroundStyle(.secondary)
				}

				Section("Revenue and Spending") {
					revenueSpendingChart
						.frame(height: FederalFinancesLayout.chartHeight)
						.listRowInsets(FederalFinancesLayout.chartInsets)
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
							HStack(spacing: FederalFinancesLayout.sourceRowSpacing) {
								Image(systemName: "checkmark.seal.fill")
									.foregroundStyle(.green)
									.frame(width: FederalFinancesLayout.sourceIconWidth)
								VStack(alignment: .leading, spacing: FederalFinancesLayout.sourceTextSpacing) {
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
		VStack(alignment: .leading, spacing: FederalFinancesLayout.summarySpacing) {
			HStack(alignment: .top) {
				VStack(alignment: .leading, spacing: FederalFinancesLayout.summaryHeaderSpacing) {
					Text("\(entry.monthName) \(Calendar.current.component(.year, from: entry.periodDate))")
						.font(.headline)
					Text("Fiscal year \(entry.fiscalYearStart)-\(String(entry.fiscalYearStart + 1).suffix(FederalFinancesLayout.shortFiscalYearDigits))")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				Spacer()
				balancePill(entry.budgetaryBalanceMillions)
			}

			HStack(spacing: FederalFinancesLayout.metricRowSpacing) {
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

				if abs(entry.yearToDateBudgetaryBalanceMillions) > abs(projection) * FederalFinancesLayout.projectionWarningMultiplier {
					Label("Year-to-date deficit has exceeded the annual budget projection by over 5%.", systemImage: "exclamationmark.triangle.fill")
						.font(.caption)
						.foregroundStyle(.orange)
				}
			}
		}
		.padding(.vertical, FederalFinancesLayout.compactVerticalPadding)
	}

	private var ytdBudgetChart: some View {
		Chart {
			ForEach(currentFiscalYearEntries) { entry in
				LineMark(
					x: .value("Month", entry.monthName),
					y: .value("Year-to-date balance", entry.yearToDateBudgetaryBalanceMillions / FederalFinancesLayout.millionsPerBillion)
				)
				.foregroundStyle(.blue)
				PointMark(
					x: .value("Month", entry.monthName),
					y: .value("Year-to-date balance", entry.yearToDateBudgetaryBalanceMillions / FederalFinancesLayout.millionsPerBillion)
				)
				.foregroundStyle(.blue)
			}

			if let projection = latestEntry?.annualBudgetProjectionMillions {
				RuleMark(y: .value("Budget projection", projection / FederalFinancesLayout.millionsPerBillion))
					.foregroundStyle(.orange)
					.lineStyle(StrokeStyle(lineWidth: FederalFinancesLayout.budgetRuleLineWidth, dash: FederalFinancesLayout.budgetRuleDashPattern))
			}
		}
		.chartYAxisLabel("$B")
	}

	private var balanceChart: some View {
		Chart(currentFiscalYearEntries) { entry in
			BarMark(
				x: .value("Month", entry.monthName),
				y: .value("Balance", entry.budgetaryBalanceMillions / FederalFinancesLayout.millionsPerBillion)
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
					y: .value("Revenue", entry.revenueMillions / FederalFinancesLayout.millionsPerBillion),
					series: .value("Type", "Revenue")
				)
				.foregroundStyle(.green)

				LineMark(
					x: .value("Month", entry.monthName),
					y: .value("Spending", entry.totalSpendingMillions / FederalFinancesLayout.millionsPerBillion),
					series: .value("Type", "Spending")
				)
				.foregroundStyle(.blue)
			}
		}
		.chartYAxisLabel("$B")
	}

	private func monthlyRow(_ entry: FiscalMonitorEntry) -> some View {
		HStack {
			VStack(alignment: .leading, spacing: FederalFinancesLayout.monthlyRowTextSpacing) {
				Text(entry.monthName)
					.font(.subheadline)
				Text("Published \(entry.publicationDate.formatted(date: .abbreviated, time: .omitted))")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			Spacer()
			VStack(alignment: .trailing, spacing: FederalFinancesLayout.monthlyRowTextSpacing) {
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
		VStack(alignment: .leading, spacing: FederalFinancesLayout.metricTextSpacing) {
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
			.padding(.horizontal, FederalFinancesLayout.balancePillHorizontalPadding)
			.padding(.vertical, FederalFinancesLayout.balancePillVerticalPadding)
			.background((value >= 0 ? Color.green : Color.red).opacity(FederalFinancesLayout.balancePillOpacity))
			.clipShape(Capsule())
	}

	private func formatCurrencyMillions(_ value: Double) -> String {
		let billions = value / FederalFinancesLayout.millionsPerBillion
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
