//
//  ContentView.swift
//  epac
//
//  Created by Sunny on 2024-12-08.
//

import SwiftUI
import SwiftData
import HorizonCalendar

/// TODO: Download and save to SwiftData and load locally when exists
struct SittingCalendarView: View {
	@EnvironmentObject var fetch: Fetch
	@Binding var selectedDate: DateComponents?

	@Environment(\.modelContext) private var modelContext
	@Environment(\.isPresented) private var isPresented
	@Environment(\.font) private var font
	@StateObject private var calendarViewProxy = CalendarViewProxy()

	@State private var dates = Set<DateComponents>()
	@State private var futureDates = Set<DateComponents>()
	@State private var currentYear: Int = Calendar.current.dateComponents([.year], from: .now).year!
	private var sittingDayCount: Int {
		dates.filter { $0.year == currentYear }.count + futureDates.filter { $0.year == currentYear }.count
	}

	private let visibleDates = ISO8601DateFormatter().date(from: "2001-01-01T23:59:59Z")!...ISO8601DateFormatter().date(from: "2025-12-31T23:59:59Z")!
	private let todayComponents = Calendar.current.dateComponents([.year, .month, .day], from: .now)
	private let yearFormatter: NumberFormatter = {
		let f = NumberFormatter()
		f.usesGroupingSeparator = false
		return f
	}()

	var body: some View {
		VStack {
			CalendarViewRepresentable(visibleDateRange: visibleDates, monthsLayout: .vertical, dataDependency: dates, proxy: calendarViewProxy)
				.days({ day in
					Text(verbatim: "\(day.day)")
						.foregroundStyle(todayComponents.sameYMD(as: day.components) ? Color(UIColor.white) : Color(UIColor.label))
						.frame(maxWidth: .infinity, maxHeight: .infinity)
						.background {
							if todayComponents.sameYMD(as: day.components) {
								Circle()
									.fill(Color(UIColor.systemRed))
							} else {
								RoundedRectangle(cornerRadius: 12)
									.fill(dates.contains(where: {$0.sameYMD(as: day.components)}) ? Color(UIColor.systemGreen) : .clear)
									.fill(futureDates.contains(where: {$0.sameYMD(as: day.components)}) ? Color(UIColor.systemGreen) : .clear)
							}
						}
				})
				.onDragEnd({ visibleDayRange, willDecelerate in
					guard !willDecelerate else { return }
					onVisibleDayRangeChanged(visibleDayRange)
				})
				.onDeceleratingEnd({ visibleDayRange in
					onVisibleDayRangeChanged(visibleDayRange)
				})
				.onDaySelection({ day in
					selectedDate = day.components
				})
				.interMonthSpacing(15)
				.verticalDayMargin(8)
				.horizontalDayMargin(8)
				.padding([.leading, .trailing, .bottom])
			HStack {
				RoundedRectangle(cornerRadius: 4)
					.fill(Color(UIColor.systemGreen))
					.frame(width: 22, height: 22, alignment: .center)
				Text("Sitting days \(sittingDayCount > 0 ? "(\(sittingDayCount) in \(yearFormatter.string(from: NSNumber(value: currentYear))!))" : "")")
			}
		}
		.task {
			if dates.isEmpty {
				await fetchSittingCalendar(currentYear)
				calendarViewProxy.scrollToMonth(containing: .now, scrollPosition: .firstFullyVisiblePosition, animated: false)
			}
			selectedDate = nil
		}
		.toolbar {
			ToolbarItem(placement: .principal) {
				VStack {
					Text("House of Commons Sitting Calendar")
						.lineLimit(0)
						.minimumScaleFactor(1)
				}
			}
		}
	}

	private func fetchSittingCalendar(_ year: Int) async {
		do {
			var calendar = try? modelContext.fetch(FetchDescriptor<SittingCalendar>(predicate: #Predicate { $0.year == year })).first
			if calendar == nil {
				try await fetch.downloadSittingCalendar(year)
				calendar = try? modelContext.fetch(FetchDescriptor<SittingCalendar>(predicate: #Predicate { $0.year == year })).first
			}
			let today = Calendar.current.startOfDay(for: .now)
			calendar?.sittings.filter { $0 < today }.map {
				Calendar.current.dateComponents([.year, .month, .day], from: $0)
			}.forEach { dates.insert($0) }
			calendar?.sittings.filter { $0 >= today }.map {
				Calendar.current.dateComponents([.year, .month, .day], from: $0)
			}.forEach { futureDates.insert($0) }
		} catch {
			Log.debug("Failed to fetch SittingCalendar count")
		}
	}

	private func onVisibleDayRangeChanged(_ visibleDayRange: DayComponentsRange) {
		if visibleDayRange.lowerBound.components.year! != currentYear {
			currentYear = visibleDayRange.lowerBound.components.year!
			Task {
				await fetchSittingCalendar(visibleDayRange.lowerBound.components.year!)
			}
		} else if visibleDayRange.upperBound.components.year! != currentYear {
			currentYear = visibleDayRange.upperBound.components.year!
			Task {
				await fetchSittingCalendar(visibleDayRange.upperBound.components.year!)
			}
		}
		if visibleDayRange.lowerBound.components.year! != visibleDayRange.upperBound.components.year! {
			let lower = Calendar.current.date(from: visibleDayRange.lowerBound.components)!
			let endOfYear = Calendar.current.date(from: DateComponents(year: visibleDayRange.lowerBound.components.year!, month: 12, day: 31))!
			let upper = Calendar.current.date(from: visibleDayRange.upperBound.components)!
			let startOfYear = Calendar.current.date(from: DateComponents(year: visibleDayRange.upperBound.components.year!, month: 1, day: 1))!

			let lowerCount = Calendar.current.dateComponents([.day], from: lower, to: endOfYear).day!
			let upperCount = Calendar.current.dateComponents([.day], from: startOfYear, to: upper).day!
			if lowerCount > upperCount {
				currentYear = visibleDayRange.lowerBound.components.year!
			} else {
				currentYear = visibleDayRange.upperBound.components.year!
			}
		}
	}
}

extension Date: @retroactive Identifiable {
	public var id: Date {
		return self
	}
}

extension DateComponents {
	func sameYMD(as components: DateComponents) -> Bool {
		return self.year == components.year && self.month == components.month && self.day == components.day
	}
}
