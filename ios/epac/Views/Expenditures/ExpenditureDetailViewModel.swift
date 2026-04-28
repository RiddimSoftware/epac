//
//  ExpenditureDetailViewModel.swift
//  epac
//

import ActivityView
import Observation
import Sentry
import SwiftUI

@MainActor
@Observable
class ExpenditureDetailViewModel {
	enum SortOption: String, CaseIterable, Identifiable {
		case date = "Date"
		case amount = "Amount"
		var id: String { rawValue }
	}

	var isLoading = false
	var sortOption: SortOption = .date
	var travelCollapsed = false
	var hospitalityCollapsed = false
	var contractsCollapsed = false
	var visibleIds: Set<String> = []

	func sortedTravelClaims(for expenditure: SummaryExpenditure) -> [TravelClaim] {
		expenditure.travelClaims.sorted {
			switch sortOption {
			case .date:   return $0.startDate > $1.startDate
			case .amount: return $0.total > $1.total
			}
		}
	}

	func sortedHospitalityDetails(for expenditure: SummaryExpenditure) -> [HospitalityExpenditure] {
		expenditure.hospitalityDetails.sorted {
			switch sortOption {
			case .date:   return $0.date > $1.date
			case .amount: return $0.total > $1.total
			}
		}
	}

	func sortedContractDetails(for expenditure: SummaryExpenditure) -> [ContractExpenditure] {
		expenditure.contractDetails.sorted {
			switch sortOption {
			case .date:   return $0.date > $1.date
			case .amount: return $0.total > $1.total
			}
		}
	}

	func handleHeaderTap(isCollapsed: Binding<Bool>, firstItemId: String, proxy: ScrollViewProxy, reduceMotion: Bool = false) {
		let animation: Animation? = reduceMotion ? nil : .snappy
		if isCollapsed.wrappedValue {
			withAnimation(animation) { isCollapsed.wrappedValue = false }
		} else {
			if visibleIds.contains(firstItemId) {
				withAnimation(animation) { isCollapsed.wrappedValue = true }
			} else {
				withAnimation(animation) { proxy.scrollTo(firstItemId, anchor: .top) }
			}
		}
	}

	@MainActor
	func loadDetails(expenditure: SummaryExpenditure, fetch: Fetch) async {
		guard expenditure.travelClaims.isEmpty && expenditure.hospitalityDetails.isEmpty && expenditure.contractDetails.isEmpty else { return }
		isLoading = true
		do {
			try await fetch.downloadDetailedExpenditures(identifier: expenditure.id)
		} catch {
			Log.error("Failed to download details: \(error.localizedDescription)")
			SentrySDK.capture(error: error)
		}
		isLoading = false
	}

	@MainActor
	func shareSummary(expenditure: SummaryExpenditure) -> ActivityItem? {
		let title = "\(expenditure.firstName) \(expenditure.lastName) (\(String(expenditure.year)) Q\(expenditure.quarter))"
		let view = VStack(alignment: .leading, spacing: 16) {
			Text(title)
				.font(.headline)
				.foregroundColor(.black)

			VStack(alignment: .leading, spacing: 8) {
				SummarySection(title: "Travel", total: expenditure.travel)
				SummarySection(title: "Hospitality", total: expenditure.hospitality)
				SummarySection(title: "Contracts", total: expenditure.contracts)
			}
			.foregroundColor(.black)

			Divider()

			HStack {
				Text("Total Expenditures").fontWeight(.bold)
				Spacer()
				Text(expenditure.total.formatted(.currency(code: "CAD"))).fontWeight(.bold)
			}
			.foregroundColor(.black)
		}
		.padding()
		.frame(width: 350)
		.background(Color.white)
		.environment(\.colorScheme, .light)

		return renderAndShare(view, title: title)
	}

	@MainActor
	func shareSection<T: Identifiable, V: View>(expenditure: SummaryExpenditure, category: String, total: Double, items: [T], @ViewBuilder rowBuilder: @escaping (T) -> V) -> ActivityItem? {
		let title = "\(expenditure.firstName) \(expenditure.lastName) (\(String(expenditure.year)) Q\(expenditure.quarter))"
		let shareItems = Array(items.prefix(5))
		let moreCount = items.count - shareItems.count

		let view = VStack(alignment: .leading, spacing: 0) {
			VStack(alignment: .leading, spacing: 4) {
				Text(title).font(.headline).foregroundColor(.black)
				HStack {
					Text(category).font(.title3).fontWeight(.bold).foregroundColor(.black)
					Spacer()
					Text(total.formatted(.currency(code: "CAD"))).font(.title3).fontWeight(.bold).foregroundColor(.black)
				}
			}
			.padding()
			.background(Color(UIColor.secondarySystemBackground))

			VStack(alignment: .leading, spacing: 0) {
				ForEach(shareItems) { item in
					rowBuilder(item)
						.padding(.horizontal)
						.padding(.vertical, 8)
						.background(Color.white)
					Divider()
				}
				if moreCount > 0 {
					Text("... and \(moreCount) more items")
						.font(.caption)
						.foregroundColor(.secondary)
						.padding()
						.frame(maxWidth: .infinity, alignment: .center)
						.background(Color.white)
				}
			}
		}
		.frame(width: 400)
		.background(Color.white)
		.environment(\.colorScheme, .light)

		return renderAndShare(view, title: "\(category) - \(title)")
	}

	@MainActor
	func shareCell<V: View>(_ view: V) -> ActivityItem? {
		let renderedView = view
			.padding()
			.frame(width: 350)
			.background(Color.white)
			.environment(\.colorScheme, .light)
		return renderAndShare(renderedView, title: "Expenditure Detail")
	}

	@MainActor
	private func renderAndShare<V: View>(_ view: V, title: String) -> ActivityItem? {
		let renderer = ImageRenderer(content: view)
		renderer.scale = UIScreen.main.scale
		if let image = renderer.uiImage {
			let source = ShareActivityItemSource(image: image, title: title)
			return ActivityItem(items: source)
		}
		return nil
	}
}
