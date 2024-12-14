//
//  ContentView.swift
//  epac
//
//  Created by Sunny on 2024-12-08.
//

import SwiftUI
import SwiftData

/// TODO: Download and save to SwiftData and load locally when exists
struct SittingCalendarView: View {
	@EnvironmentObject var fetch: Fetch
	@Environment(\.modelContext) private var modelContext
	@Environment(\.isPresented) private var isPresented
	@Environment(\.font) private var font
	@State private var dates = Set<DateComponents>()
	@Binding var selectedDate: DateComponents?

	var body: some View {
		VStack {
			CalendarView(selection: $selectedDate)
				.decorating(dates, systemImage: "message", color: .gray, size: .large)
				.selectable(updatingOnChangeOf: selectedDate, canSelectDate: { c in
					dates.contains(where: { $0.year == c.year && $0.month == c.month && $0.day == c.day })
				})
				.font(font)
		}
		.task {
			let currentYear = Calendar.current.dateComponents([.year], from: .now).year!
			do {
				let calendar = try await fetch.sittingCalendar(currentYear)
				let today = Calendar.current.startOfDay(for: .now)
				calendar.sittings.filter { $0 < today }.map {
					Calendar.current.dateComponents([.year, .month, .day], from: $0)
				}.forEach { dates.insert($0) }
			} catch {
				print("Failed to fetch SittingCalendar count")
			}
		}
	}
}

extension Date: @retroactive Identifiable {
	public var id: Date {
		return self
	}
}
