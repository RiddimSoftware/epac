//
//  ContentView.swift
//  epac
//
//  Created by Sunny on 2024-12-08.
//

import SwiftUI
import SwiftData

struct SittingCalendarView: View {
	@EnvironmentObject var downloader: Downloader
	@Environment(\.modelContext) private var modelContext
	@Environment(\.isPresented) private var isPresented
	@Query(FetchDescriptor<SittingCalendar>(predicate: #Predicate { $0.year == 2024 })) private var sittingCalendar: [SittingCalendar]
	@State private var dates = Set<DateComponents>()

	var body: some View {
		VStack {
			CalendarView()
				.decorating(dates, systemImage: "message", color: .blue, size: .small)
		}
		.task {
			let currentYear = Calendar.current.dateComponents([.year], from: .now).year!
			do {
				let count = try modelContext.fetchCount(FetchDescriptor<SittingCalendar>(predicate: #Predicate { $0.year == currentYear }))
				if count == 0 {
					do {
						let dates = try await downloader.downloadCalendar(year: currentYear)
						let calendar = SittingCalendar(year: currentYear, sittings: dates)
						modelContext.insert(calendar)
						let today = Calendar.current.startOfDay(for: .now)
						dates.filter { $0 < today }.map {
							Calendar.current.dateComponents([.year, .month, .day], from: $0)
						}.forEach { self.dates.insert($0) }
					} catch {
						print("Failed to download sitting calendar \(currentYear)")
					}
				}
			} catch {
				print("Failed to fetch SittingCalendar count")
			}
		}
		.onChange(of: sittingCalendar) { oldValue, newValue in
			print(newValue)
		}
//		.task {
//			do {
//				let today = Calendar.current.startOfDay(for: .now)
//				let dates = try await model.getCalendar().filter { $0 < today }.sorted(by: >)
//				self.dates = dates
//				let orders = try await model.getOrdersOfBusiness(forDate: dates.first!)
//				print(orders[1].subjectsofbusiness.first?.speeches.first)
//			} catch {
//				print("Failed to get dates \(error.localizedDescription)")
//			}
//		}
//		.onChange(of: isPresented) { oldValue, newValue in
//			if !oldValue, newValue {
//				Task {
//					let dates = try await model.getCalendar()
//					self.dates = dates
//				}
//			}
//		}
	}
}

extension Date: @retroactive Identifiable {
	public var id: Date {
		return self
	}
}

#Preview {
	SittingCalendarView()
		.modelContainer(for: Item.self, inMemory: true)
}
