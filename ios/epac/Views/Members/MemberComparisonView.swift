//
//  MemberComparisonView.swift
//  epac
//

import SwiftUI
import SwiftData

struct MemberComparisonView: View {
	let memberA: ParliamentMember
	let memberB: ParliamentMember

	@Query private var allExpenditures: [SummaryExpenditure]

	private func totals(for member: ParliamentMember) -> (travel: Double, hospitality: Double, contracts: Double) {
		let rows = allExpenditures.filter {
			$0.firstName.caseInsensitiveCompare(member.firstName) == .orderedSame &&
			$0.lastName.caseInsensitiveCompare(member.lastName) == .orderedSame
		}
		return (
			rows.reduce(0) { $0 + $1.travel },
			rows.reduce(0) { $0 + $1.hospitality },
			rows.reduce(0) { $0 + $1.contracts }
		)
	}

	var body: some View {
		ScrollView {
			VStack(spacing: 20) {
				memberHeaderCard
				expenditureSection
			}
			.padding()
		}
		.navigationTitle("Comparison")
		.navigationBarTitleDisplayMode(.inline)
	}

	private var memberHeaderCard: some View {
		HStack(alignment: .top, spacing: 0) {
			memberColumn(memberA)
			Divider()
			memberColumn(memberB)
		}
		.background(Color(.secondarySystemBackground))
		.cornerRadius(12)
	}

	private func memberColumn(_ member: ParliamentMember) -> some View {
		VStack(spacing: 8) {
			MemberAvatar(member: member)
				.frame(width: 72, height: 72)
			Text(member.name)
				.font(.headline)
				.multilineTextAlignment(.center)
			Text(member.party.fullName)
				.font(.caption)
				.foregroundStyle(member.party.swiftUIColor)
			Text(member.riding)
				.font(.caption2)
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
			Text(member.province.rawValue)
				.font(.caption2)
				.foregroundStyle(.secondary)
		}
		.padding()
		.frame(maxWidth: .infinity)
	}

	private var expenditureSection: some View {
		let a = totals(for: memberA)
		let b = totals(for: memberB)
		let totalA = a.travel + a.hospitality + a.contracts
		let totalB = b.travel + b.hospitality + b.contracts

		return VStack(alignment: .leading, spacing: 0) {
			Text("Expenditures (all periods)")
				.font(.headline)
				.padding(.bottom, 12)

			ComparisonRow(label: "Travel",      valueA: a.travel,      valueB: b.travel)
			Divider()
			ComparisonRow(label: "Hospitality", valueA: a.hospitality, valueB: b.hospitality)
			Divider()
			ComparisonRow(label: "Contracts",   valueA: a.contracts,   valueB: b.contracts)
			Divider()
			ComparisonRow(label: "Total",       valueA: totalA,        valueB: totalB, bold: true)
		}
		.padding()
		.background(Color(.secondarySystemBackground))
		.cornerRadius(12)
	}
}

private struct ComparisonRow: View {
	let label: String
	let valueA: Double
	let valueB: Double
	var bold = false

	private func formatted(_ v: Double) -> String {
		Decimal(v).formatted(.currency(code: "CAD"))
	}

	var body: some View {
		// When values are equal neither side "wins", so both render primary.
		// When one is strictly higher it gets primary emphasis; the lower gets secondary.
		let aStyle: HierarchicalShapeStyle = valueA >= valueB ? .primary : .secondary
		let bStyle: HierarchicalShapeStyle = valueB >= valueA ? .primary : .secondary

		HStack {
			Text(formatted(valueA))
				.frame(maxWidth: .infinity, alignment: .leading)
				.foregroundStyle(aStyle)
			Text(label)
				.frame(maxWidth: .infinity, alignment: .center)
				.foregroundStyle(.secondary)
			Text(formatted(valueB))
				.frame(maxWidth: .infinity, alignment: .trailing)
				.foregroundStyle(bStyle)
		}
		.font(bold ? .headline : .subheadline)
		.padding(.vertical, 6)
	}
}
