//
//  ExpendituresViewModel.swift
//  epac
//

import Observation
import SwiftUI
import ActivityView
import Sentry

@MainActor
@Observable
class ExpendituresViewModel {
	enum SortOrder: String, CaseIterable, Identifiable {
		case name = "Name"
		case total = "Total"
		case travel = "Travel"
		case hospitality = "Hospitality"
		case contracts = "Contracts"

		var id: String { rawValue }
	}

	struct ExpenditurePeriod: Hashable, Identifiable {
		var id: String { "\(year) Q\(quarter)" }
		let year: Int
		let quarter: Int
	}

	let periods: [ExpenditurePeriod] = {
		let now = Date()
		let cal = Calendar.current
		let currentYear = cal.component(.year, from: now)
		let currentQuarter = (cal.component(.month, from: now) - 1) / 3 + 1
		var p: [ExpenditurePeriod] = []
		for year in (2021...currentYear).reversed() {
			let maxQ = (year == currentYear) ? currentQuarter : 4
			for quarter in stride(from: maxQ, through: 1, by: -1) {
				if year == 2021 && quarter < 2 { continue }
				p.append(ExpenditurePeriod(year: year, quarter: quarter))
			}
		}
		return p
	}()

	var selectedYear: Int = Calendar.current.component(.year, from: Date())
	var selectedQuarter: Int = (Calendar.current.component(.month, from: Date()) - 1) / 3 + 1
	var searchText = ""
	var sortOrder: SortOrder = .total
	var isLoading = false
	var loadFailed = false

	func filteredExpenditures(from expenditures: [SummaryExpenditure]) -> [SummaryExpenditure] {
		let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
		let filtered = expenditures.filter { expenditure in
			expenditure.year == selectedYear && expenditure.quarter == selectedQuarter &&
			(trimmed.isEmpty ||
			 expenditure.firstName.lowercased().contains(trimmed) ||
			 expenditure.lastName.lowercased().contains(trimmed))
		}
		return filtered.sorted { a, b in
			switch sortOrder {
			case .name:        return a.lastName < b.lastName
			case .total:       return a.total > b.total
			case .travel:      return a.travel > b.travel
			case .hospitality: return a.hospitality > b.hospitality
			case .contracts:   return a.contracts > b.contracts
			}
		}
	}

	@MainActor
	func loadData(expenditures: [SummaryExpenditure], fetch: Fetch) async {
		loadFailed = false
		let exists = expenditures.contains { $0.year == selectedYear && $0.quarter == selectedQuarter }
		if !exists {
			isLoading = true
			do {
				try await fetch.expenditures(year: selectedYear, quarter: selectedQuarter)
			} catch {
				Log.error("Failed to load expenditures: \(error.localizedDescription)")
				SentrySDK.capture(error: error)
				loadFailed = true
			}
			isLoading = false
		}
	}

	@MainActor
	func shareExpenditures(expenditures: [SummaryExpenditure], members: [ParliamentMember]) -> ActivityItem? {
		let view = VStack(spacing: 0) {
			Text("Expenditures - \(selectedYear) Q\(selectedQuarter)")
				.font(.headline)
				.padding()

			ForEach(expenditures.prefix(20)) { expenditure in
				let member = members.first { $0.firstName == expenditure.firstName && $0.lastName == expenditure.lastName }
				ExpenditureRow(expenditure: expenditure, member: member)
					.padding()
				Divider()
			}

			if expenditures.count > 20 {
				Text("... and \(expenditures.count - 20) more")
					.font(.caption)
					.foregroundColor(.secondary)
					.padding()
			}
		}
		.frame(width: 400)
		.background(Color.appBackground)

		let renderer = ImageRenderer(content: view)
		renderer.scale = UIScreen.main.scale
		if let image = renderer.uiImage {
			let source = ShareActivityItemSource(image: image, title: "Expenditures - \(selectedYear) Q\(selectedQuarter)")
			return ActivityItem(items: source)
		}
		return nil
	}
}
