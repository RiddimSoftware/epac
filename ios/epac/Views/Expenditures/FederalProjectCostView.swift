//
//  FederalProjectCostView.swift
//  epac
//

import SwiftUI
import SwiftData

// Shows the federal government's project cost lifecycle: from initial
// estimate through appropriated budget, actual spending, and audit findings.
//
// Large contracts from the existing MP expenditure data surface as one
// observable slice of government spending. Full project-level lifecycle
// data lives in Treasury Board and the Auditor General's public reports.
struct FederalProjectCostView: View {
	@Environment(\.openURL) private var openURL
	@Query private var topContracts: [ContractExpenditure]

	init() {
		var descriptor = FetchDescriptor<ContractExpenditure>(
			sortBy: [SortDescriptor(\.total, order: .reverse)]
		)
		descriptor.fetchLimit = 20
		_topContracts = Query(descriptor)
	}

	var body: some View {
		List {
			Section {
				lifecycleCard
			}

			if !topContracts.isEmpty {
				Section("Largest MP Office Contracts (All MPs)") {
					ForEach(topContracts) { contract in
						contractRow(contract)
					}
					Text("Showing top 20 by value. Full contract data is available in each MP's profile.")
						.font(.caption)
						.foregroundStyle(.secondary)
						.listRowBackground(Color.clear)
				}
			}

			Section("Official Sources") {
				sourceRow(
					title: "Treasury Board Contract Disclosures",
					subtitle: "All federal contracts over $10,000 — proactive disclosure",
					icon: "doc.text.fill",
					color: .blue,
					url: "https://search.open.canada.ca/contracts/"
				)
				sourceRow(
					title: "Parliamentary Budget Officer",
					subtitle: "Independent cost estimates for major programs and bills",
					icon: "chart.line.uptrend.xyaxis",
					color: .purple,
					url: "https://www.pbo-dpb.ca/en/publications"
				)
				sourceRow(
					title: "Auditor General Reports",
					subtitle: "Performance audits finding cost overruns and inefficiencies",
					icon: "magnifyingglass.circle.fill",
					color: .red,
					url: "https://www.oag-bvg.gc.ca/internet/English/parl_lp_e_933.html"
				)
				sourceRow(
					title: "Public Accounts of Canada",
					subtitle: "Annual financial statements — actuals vs. estimates",
					icon: "book.closed.fill",
					color: .green,
					url: "https://www.tpsgc-pwgsc.gc.ca/recgen/cpc-pac/index-eng.html"
				)
			}
		}
		.listStyle(.insetGrouped)
		.navigationTitle("Project Cost Lifecycle")
		.navigationBarTitleDisplayMode(.inline)
	}

	// MARK: - Lifecycle explainer card

	private var lifecycleCard: some View {
		VStack(alignment: .leading, spacing: 12) {
			Text("How federal project costs work")
				.font(.headline)

			HStack(alignment: .top, spacing: 0) {
				ForEach(Self.lifecycleSteps, id: \.title) { step in
					VStack(spacing: 4) {
						ZStack {
							Circle()
								.fill(step.color.opacity(0.15))
								.frame(width: 36, height: 36)
							Image(systemName: step.icon)
								.foregroundStyle(step.color)
								.font(.system(size: 14))
						}
						Text(step.title)
							.font(.system(.caption2, weight: .semibold))
							.multilineTextAlignment(.center)
							.foregroundStyle(.secondary)
					}
					.frame(maxWidth: .infinity)
					if step.title != Self.lifecycleSteps.last?.title {
						Image(systemName: "arrow.right")
							.font(.caption2)
							.foregroundStyle(.tertiary)
							.frame(width: 12)
							.padding(.top, 10)
					}
				}
			}
			.padding(.vertical, 4)

			Text("Estimates often differ from actual spending. The PBO provides independent costings; the Auditor General audits results.")
				.font(.caption)
				.foregroundStyle(.secondary)
		}
		.padding(.vertical, 4)
	}

	private struct LifecycleStep { let title: String; let icon: String; let color: Color }
	private static let lifecycleSteps: [LifecycleStep] = [
		LifecycleStep(title: "Estimate",  icon: "pencil",         color: .blue),
		LifecycleStep(title: "Budget",    icon: "dollarsign",     color: .orange),
		LifecycleStep(title: "Contracts", icon: "doc.text",       color: .purple),
		LifecycleStep(title: "Actual",    icon: "chart.bar",      color: .green),
		LifecycleStep(title: "Audit",     icon: "checkmark.seal", color: .red),
	]

	// MARK: - Contract rows

	private func contractRow(_ contract: ContractExpenditure) -> some View {
		VStack(alignment: .leading, spacing: 3) {
			Text(contract.supplier)
				.font(.subheadline)
				.lineLimit(2)
			Text(contract.details.isEmpty ? "Contract" : contract.details)
				.font(.caption)
				.foregroundStyle(.secondary)
				.lineLimit(2)
			HStack {
				Text(contract.date.formatted(date: .abbreviated, time: .omitted))
					.font(.caption2)
					.foregroundStyle(.tertiary)
				Spacer()
				Text(contract.total, format: .currency(code: "CAD"))
					.font(.caption.bold())
					.foregroundStyle(.primary)
			}
		}
		.padding(.vertical, 2)
	}

	// MARK: - Source rows

	private func sourceRow(title: String, subtitle: String, icon: String, color: Color, url: String) -> some View {
		Button { if let u = URL(string: url) { openURL(u) } } label: {
			HStack(spacing: 12) {
				Image(systemName: icon)
					.foregroundStyle(color)
					.frame(width: 28)
					.accessibilityHidden(true)
				VStack(alignment: .leading, spacing: 2) {
					Text(title).font(.subheadline).foregroundStyle(.primary)
					Text(subtitle).font(.caption).foregroundStyle(.secondary)
				}
				Spacer()
				Image(systemName: "arrow.up.right.square").font(.caption).foregroundStyle(.tertiary)
			}
		}
	}
}
