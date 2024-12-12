//
//  ContentView.swift
//  epac
//
//  Created by Sunny on 2024-12-08.
//

import SwiftUI
import SwiftData

struct ParliamentDateView: View {
	@EnvironmentObject var model: Model
	@Environment(\.isPresented) private var isPresented
	@State private var dates = [Date]()

	var body: some View {
		List {
			ForEach(dates) { date in
				if Calendar.current.isDateInYesterday(date) {
					Text("Yesterday")
				} else {
					Text(date.formatted(date: .complete, time: .omitted))
				}
			}
		}
		.task {
			do {
				let today = Calendar.current.startOfDay(for: .now)
				let dates = try await model.getCalendar().filter { $0 < today }.sorted(by: >)
				self.dates = dates
				let orders = try await model.getOrdersOfBusiness(forDate: dates.first!)
				print(orders.first)
			} catch {
				print("Failed to get dates \(error.localizedDescription)")
			}
		}
		.onChange(of: isPresented) { oldValue, newValue in
			if !oldValue, newValue {
				Task {
					let dates = try await model.getCalendar()
					self.dates = dates
				}
			}
		}
	}
}

extension Date: @retroactive Identifiable {
	public var id: Date {
		return self
	}
}

#Preview {
	ParliamentDateView()
		.modelContainer(for: Item.self, inMemory: true)
}
