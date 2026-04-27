//
//  ContentView.swift
//  epac
//
//  Created by Sunny on 2024-12-08.
//

import SwiftUI
import SwiftData
import HorizonCalendar

struct SittingCalendarView: View {
	@EnvironmentObject var fetch: Fetch
	@Binding var selectedDate: DateComponents?

	@Environment(\.modelContext) private var modelContext
	@Environment(\.isPresented) private var isPresented
	@Environment(\.font) private var font
	@StateObject private var calendarViewProxy = CalendarViewProxy()

	@State private var viewModel = SittingCalendarViewModel()

	private let visibleDates = ISO8601DateFormatter().date(from: "2001-01-01T23:59:59Z")!...ISO8601DateFormatter().date(from: "2026-12-31T23:59:59Z")!
	private let todayComponents = Calendar.current.dateComponents([.year, .month, .day], from: .now)
	private let yearFormatter: NumberFormatter = {
		let f = NumberFormatter()
		f.usesGroupingSeparator = false
		return f
	}()

	var body: some View {
		VStack {
			CalendarViewRepresentable(visibleDateRange: visibleDates, monthsLayout: .vertical, dataDependency: viewModel.dates, proxy: calendarViewProxy)
				.days({ day in
					let isToday = todayComponents.sameYMD(as: day.components)
					let isPastSitting = viewModel.dates.contains(where: { $0.sameYMD(as: day.components) })
					let isFutureSitting = viewModel.futureDates.contains(where: { $0.sameYMD(as: day.components) })

					Text(verbatim: "\(day.day)")
						.foregroundStyle(isToday ? Color(UIColor.white) : Color(UIColor.label))
						.frame(maxWidth: .infinity, maxHeight: .infinity)
						.background {
							if isToday {
								Circle()
									.fill(Color(UIColor.systemRed))
							} else if isPastSitting {
								RoundedRectangle(cornerRadius: 12)
									.fill(Color(UIColor.systemGreen))
							} else if isFutureSitting {
								RoundedRectangle(cornerRadius: 12)
									.stroke(Color(UIColor.systemGreen), lineWidth: 2)
							} else {
								Color.clear
							}
						}
				})
				.onDragEnd({ visibleDayRange, willDecelerate in
					guard !willDecelerate else { return }
					viewModel.onVisibleDayRangeChanged(visibleDayRange, modelContext: modelContext, fetch: fetch)
				})
				.onDeceleratingEnd({ visibleDayRange in
					viewModel.onVisibleDayRangeChanged(visibleDayRange, modelContext: modelContext, fetch: fetch)
				})
				.onDaySelection({ day in
					selectedDate = day.components
				})
				.interMonthSpacing(15)
				.verticalDayMargin(8)
				.horizontalDayMargin(8)
				.padding([.leading, .trailing, .bottom])
			VStack(alignment: .leading, spacing: 12) {
				HStack(spacing: 12) {
					RoundedRectangle(cornerRadius: 6)
						.fill(Color(UIColor.systemGreen))
						.frame(width: 24, height: 24)
					Text("Sitting days")
						.font(.subheadline)
						.fontWeight(.medium)
					if viewModel.sittingDayCount > 0 {
						Text("(\(viewModel.sittingDayCount) in \(yearFormatter.string(from: NSNumber(value: viewModel.currentYear))!))")
							.font(.caption)
							.foregroundColor(.secondary)
					}
				}
				
				HStack(spacing: 20) {
					HStack(spacing: 8) {
						Circle()
							.fill(Color(UIColor.systemRed))
							.frame(width: 16, height: 16)
						Text("Today")
					}
					.contentShape(Rectangle())
					.onTapGesture {
						calendarViewProxy.scrollToMonth(containing: .now, scrollPosition: .firstFullyVisiblePosition, animated: false)
					}
					
					HStack(spacing: 8) {
						RoundedRectangle(cornerRadius: 4)
							.stroke(Color(UIColor.systemGreen), lineWidth: 2)
							.frame(width: 16, height: 16)
						Text("Upcoming")
					}
				}
				.font(.caption)
				.foregroundColor(.secondary)
			}
			.padding(.horizontal)
			.padding(.bottom, 8)
		}
		.frame(maxWidth: 500)
		.frame(maxWidth: .infinity)
		.task {
			if viewModel.dates.isEmpty {
				await viewModel.fetchSittingCalendar(viewModel.currentYear, modelContext: modelContext, fetch: fetch)
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

struct NonSittingDayView: View {
    let date: Date
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "building.columns.fill")
                .font(.system(size: 80))
                .foregroundColor(.accentColor)
                .padding(.top, 40)
            
            VStack(spacing: 8) {
                Text(date.formatted(date: .long, time: .omitted))
                    .font(.title3)
                    .fontWeight(.bold)
                
                Text("The House is not sitting today.")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            
            Divider()
                .padding(.horizontal, 40)
            
            VStack(alignment: .leading, spacing: 16) {
                Label("Committee Meetings", systemImage: "person.3.fill")
                    .font(.headline)
                Text("Committees often meet even when the House is not in session to study legislation and specific issues in depth.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Label("Historical Throwback", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                Text("Did you know? The first session of Canada's 1st Parliament opened on November 6, 1867.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 30)
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: 500)
        .frame(maxWidth: .infinity)
        .navigationTitle("Recess")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        NonSittingDayView(date: .now)
    }
}
